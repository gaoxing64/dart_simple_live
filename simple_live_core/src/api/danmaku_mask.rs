use regex::Regex;
use std::collections::HashMap;
use xxhash_rust::xxh3::xxh3_64;

/// DanmakuMask: 滑动窗口 + 分桶 + 频控
#[flutter_rust_bridge::frb(opaque)]
pub struct DanmakuMask {
    base_window_ms: u32,     // 基础窗口（ms）
    bucket_count: u16,       // 桶数量
    max_frequency: u16,      // 最大允许频次

    use_normalization: bool,
    use_frequency_control: bool,

    // 运行时状态
    window_ms: u32,
    bucket_size_ms: u32,

    current_bucket: usize,  // Vec 索引
    last_shift_ms: u64,     // 上次滑动的时间戳（ms）

    // 桶内记录每个 hash 的出现次数（保证频控计数准确）
    buckets: Vec<HashMap<u64, u16>>,
    // 全局滑动窗口内每个 hash 的总次数
    freq_map: HashMap<u64, u16>,

    norm_re_space: Option<Regex>,
    norm_re_punct: Option<Regex>,
}

#[flutter_rust_bridge::frb(sync)]
impl DanmakuMask {
    pub fn new(
        base_window_ms: u32,
        bucket_count: u16,
        use_normalization: bool,
        use_frequency_control: bool,
        max_frequency: u16,
    ) -> Self {
        let bucket_count_usize = bucket_count.max(1) as usize;
        let bucket_size_ms = base_window_ms / bucket_count.max(1) as u32;

        let norm_re_space = use_normalization
            .then(|| Regex::new(r"\s+").unwrap());
        let norm_re_punct = use_normalization
            .then(|| Regex::new(r"[~!！?？,.，。]").unwrap());

        Self {
            base_window_ms,
            bucket_count,
            max_frequency,
            use_normalization,
            use_frequency_control,
            window_ms: base_window_ms,
            bucket_size_ms,
            current_bucket: 0,
            last_shift_ms: 0,
            // 用 HashMap 计数，避免去重时计数虚增
            buckets: (0..bucket_count_usize)
                .map(|_| HashMap::with_capacity(128))
                .collect(),
            freq_map: HashMap::with_capacity(1024),
            norm_re_space,
            norm_re_punct,
        }
    }

    /// 文本归一化
    fn normalize(&self, text: &str) -> String {
        if !self.use_normalization {
            return text.to_owned();
        }

        let mut s = text.trim().to_lowercase();
        if let Some(re) = &self.norm_re_space {
            s = re.replace_all(&s, "").to_string();
        }
        if let Some(re) = &self.norm_re_punct {
            s = re.replace_all(&s, "").to_string();
        }
        s
    }

    /// 滑动窗口，清理过期桶
    fn shift_if_needed(&mut self, now_ms: u64) {
        if self.last_shift_ms == 0 {
            self.last_shift_ms = now_ms;
            return;
        }

        while now_ms.saturating_sub(self.last_shift_ms) >= self.bucket_size_ms as u64 {
            self.last_shift_ms += self.bucket_size_ms as u64;
            self.current_bucket = (self.current_bucket + 1) % self.bucket_count as usize;

            // 清理即将被覆盖的桶（即将成为当前桶的那个旧桶）
            let expired = &mut self.buckets[self.current_bucket];
            for (&hash, &count) in expired.iter() {
                if let Some(v) = self.freq_map.get_mut(&hash) {
                    // 减去该桶内的出现次数，避免计数残留
                    if *v <= count {
                        self.freq_map.remove(&hash);
                    } else {
                        *v -= count;
                    }
                }
            }
            expired.clear();
        }
    }

    /// 重置状态
    pub fn reset(&mut self) {
        for bucket in &mut self.buckets {
            bucket.clear();
        }
        self.freq_map.clear();
        self.current_bucket = 0;
        self.last_shift_ms = 0;
        // window_ms 和 bucket_size_ms 无需改变，它们由构造函数固定
    }

    pub fn dispose(self) {
        // 消费所有权
    }
}

#[flutter_rust_bridge::frb]
impl DanmakuMask {
    /// 批量判断是否允许
    /// 返回 Vec<u8>：1 = 允许，0 = 屏蔽
    pub fn allow_list_batch(
        &mut self,
        texts: Vec<String>,
        now_ms: u64,
    ) -> Vec<u8> {
        self.shift_if_needed(now_ms);

        let mut results = Vec::with_capacity(texts.len());

        for text in texts {
            let normalized = self.normalize(&text);
            let hash = xxh3_64(normalized.as_bytes());

            // 确定当前实际允许的最大次数
            let effective_max: u16 = if self.use_frequency_control {
                self.max_frequency
            } else {
                1
            };

            let freq = *self.freq_map.get(&hash).unwrap_or(&0);
            let allowed = freq < effective_max;

            if allowed {
                let bucket = &mut self.buckets[self.current_bucket];
                *bucket.entry(hash).or_insert(0) += 1;
                *self.freq_map.entry(hash).or_insert(0) += 1;
            }

            results.push(if allowed { 1 } else { 0 });
        }

        results
    }
}

/// 合并模式的一组重复弹幕（merge_list_batch 的返回项）。
///
/// 与屏蔽模式（allow_list_batch）互斥：合并模式不丢弹幕，而是把窗口内的
/// 重复文本聚成一条带计数的展示项，保留直播间的热闹氛围。
pub struct DanmakuMergeGroup {
    /// 归一化文本：窗口内同一 key 的重复都会归到同一条展示项
    pub key: String,
    /// 本批中该组**首次出现**的下标（取该条消息的用户名/颜色/表情做展示）
    pub first_index: u32,
    /// 计入本批后，该 key 在滑动窗口内的累计出现次数
    pub window_count: u32,
    /// 本批之前窗口内没有该 key：调用方应新建展示项；false 表示更新已有展示项
    pub is_new: bool,
}

#[flutter_rust_bridge::frb]
impl DanmakuMask {
    /// 合并模式的批量分组：按归一化文本把本批弹幕聚组，并给出窗口累计计数。
    ///
    /// 与 [DanmakuMask::allow_list_batch] 共享同一套滑动窗口/分桶计数，
    /// 但**不使用 max_frequency**——合并的语义就是所有重复都算进同一条，
    /// 计数本身就是氛围信息，不需要上限。两种模式按批二选一调用。
    pub fn merge_list_batch(
        &mut self,
        texts: Vec<String>,
        now_ms: u64,
    ) -> Vec<DanmakuMergeGroup> {
        self.shift_if_needed(now_ms);

        // 归一化分桶，保持首次出现顺序（聊天区按此顺序追加）
        let mut order: Vec<(String, u32, u32)> = Vec::new(); // (norm, first_index, batch_count)
        let mut index: HashMap<String, usize> = HashMap::with_capacity(texts.len());

        for (i, text) in texts.iter().enumerate() {
            let norm = self.normalize(text);
            match index.get(&norm) {
                Some(&gi) => order[gi].2 = order[gi].2.saturating_add(1),
                None => {
                    index.insert(norm.clone(), order.len());
                    order.push((norm, i as u32, 1));
                }
            }
        }

        let mut results = Vec::with_capacity(order.len());
        for (norm, first_index, batch_count) in order {
            let hash = xxh3_64(norm.as_bytes());
            let prior = *self.freq_map.get(&hash).unwrap_or(&0) as u32;
            let step = batch_count.min(u16::MAX as u32) as u16;

            // 每次出现都计入窗口计数（合并模式不设频控上限）。
            // 内部计数沿用 u16（与屏蔽模式共用结构），极端刷屏时饱和；
            // 展示用的 window_count 走 u32，单批计数不会因饱和丢数。
            {
                let c = self.buckets[self.current_bucket].entry(hash).or_insert(0);
                *c = c.saturating_add(step);
            }
            {
                let c = self.freq_map.entry(hash).or_insert(0);
                *c = c.saturating_add(step);
            }

            results.push(DanmakuMergeGroup {
                key: norm,
                first_index,
                window_count: prior + batch_count,
                is_new: prior == 0,
            });
        }

        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mask() -> DanmakuMask {
        DanmakuMask::new(10_000, 10, true, true, 3)
    }

    #[test]
    fn merge_groups_by_normalized_text_in_first_seen_order() {
        let mut m = mask();
        let groups = m.merge_list_batch(
            vec!["666".into(), "777".into(), "666".into(), "哈 哈哈哈".into(), "哈哈哈哈".into()],
            1_000,
        );
        assert_eq!(groups.len(), 3);
        assert_eq!(groups[0].key, "666");
        assert_eq!(groups[0].first_index, 0);
        assert_eq!(groups[0].window_count, 2);
        assert!(groups[0].is_new);
        assert_eq!(groups[1].key, "777");
        assert_eq!(groups[1].window_count, 1);
        // 归一化去掉空格后 "哈 哈哈哈" 与 "哈哈哈哈" 同组，取首现位置与文本
        assert_eq!(groups[2].key, "哈哈哈哈");
        assert_eq!(groups[2].first_index, 3);
        assert_eq!(groups[2].window_count, 2);
    }

    #[test]
    fn merge_accumulates_across_batches_and_flags_new() {
        let mut m = mask();
        let g1 = m.merge_list_batch(vec!["666".into()], 1_000);
        assert!(g1[0].is_new);
        assert_eq!(g1[0].window_count, 1);

        let g2 = m.merge_list_batch(vec!["666".into(), "666".into()], 2_000);
        assert!(!g2[0].is_new);
        assert_eq!(g2[0].window_count, 3);
    }

    #[test]
    fn merge_window_slides_out_and_entry_becomes_new_again() {
        let mut m = mask();
        m.merge_list_batch(vec!["666".into()], 1_000);
        // 窗口 10s：11s 后旧计数滑出
        let g = m.merge_list_batch(vec!["666".into()], 12_000);
        assert!(g[0].is_new);
        assert_eq!(g[0].window_count, 1);
    }

    #[test]
    fn merge_ignores_frequency_cap() {
        let mut m = mask();
        // 频控上限 3：合并模式应照样计数不封顶
        let g = m.merge_list_batch(vec!["666".into(); 10], 1_000);
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].window_count, 10);
    }

    #[test]
    fn merge_storm_does_not_overflow_counters() {
        let mut m = mask();
        let batch: Vec<String> = vec!["666".into(); 70_000];
        let g = m.merge_list_batch(batch, 1_000);
        assert_eq!(g[0].window_count, 70_000); // 展示计数走 u32，单批不丢数
        // 再来一批也不 panic：内部 u16 计数在 65535 饱和，展示计数只增不减
        let g2 = m.merge_list_batch(vec!["666".into(); 70_000], 1_500);
        assert!(g2[0].window_count > g[0].window_count);
    }

    #[test]
    fn merge_normalization_disabled_uses_raw_text() {
        let mut m = DanmakuMask::new(10_000, 10, false, true, 3);
        let g = m.merge_list_batch(vec!["哈 哈".into(), "哈哈哈哈".into()], 1_000);
        assert_eq!(g.len(), 2);
    }
}
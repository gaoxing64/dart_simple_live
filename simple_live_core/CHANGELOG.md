## 1.1.0

- `LiveSite.getRecommendRooms` / `getCategoryRooms` 新增可选具名参数 `pageSize`：
  供调用方按窗口宽度调整单页条数，当前仅 bilibili 推荐流实际使用
  （`page_size` 参数化，默认 30），其余平台接受并忽略。
- ⚠️ **对实现 `LiveSite` 的下游是破坏性变更**：实现类必须同步补上
  `int? pageSize` 参数才能编译通过。仅调用（不实现）该接口的用法不受影响。
- `DouyuSite.getRecommendRooms` 不再依赖已失效的服务端 `pgcnt` 字段
  （该接口实测恒为 0），改为「本页非空即还有更多」。
  `DouyuSite.getCategoryRooms` 走另一接口，其 `pgcnt` 仍有效，判定保持不变。

## 1.0.0

- Initial version.

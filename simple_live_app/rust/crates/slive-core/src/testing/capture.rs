//! 捕获日志的 `log::Log` 实现（AC-40 断言日志不含凭证明文）。

use std::sync::{Arc, Mutex};

/// 进程内捕获日志的实现：把每条日志文本存进内存供断言。
pub struct CaptureLogger {
    messages: Mutex<Vec<String>>,
}

impl Default for CaptureLogger {
    fn default() -> Self {
        Self::new()
    }
}

impl CaptureLogger {
    /// 新建。
    pub fn new() -> Self {
        Self {
            messages: Mutex::new(Vec::new()),
        }
    }

    /// 安装为全局 logger（幂等：若已设置则忽略）。返回可查询的句柄。
    pub fn install() -> Arc<Self> {
        let logger = Arc::new(Self::new());
        let _ = log::set_boxed_logger(Box::new(ArcLogger(Arc::clone(&logger))));
        log::set_max_level(log::LevelFilter::Debug);
        logger
    }

    /// 已捕获的日志文本。
    pub fn messages(&self) -> Vec<String> {
        self.messages.lock().expect("log poisoned").clone()
    }
}

impl log::Log for CaptureLogger {
    fn enabled(&self, _metadata: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        self.messages
            .lock()
            .expect("log poisoned")
            .push(format!("{}", record.args()));
    }

    fn flush(&self) {}
}

struct ArcLogger(Arc<CaptureLogger>);

impl log::Log for ArcLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        self.0.enabled(metadata)
    }
    fn log(&self, record: &log::Record) {
        self.0.log(record);
    }
    fn flush(&self) {
        self.0.flush();
    }
}

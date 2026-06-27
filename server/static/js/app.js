(function () {
  const formatter = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });

  document.querySelectorAll("time[data-time]").forEach((node) => {
    const raw = node.dataset.time;
    if (!raw) return;
    const date = new Date(raw);
    if (Number.isNaN(date.getTime())) return;
    node.textContent = formatter.format(date).replace(/\//g, "-");
    node.title = raw;
  });

  const labelMap = {
    login: "登录",
    mount: "挂载",
    system: "系统",
    sync: "同步",
    agent: "Agent",
    storage: "存储",
    user: "用户",
    error: "错误",
    warning: "警告",
    info: "信息",
  };

  const levelMap = {
    success: ["login", "mount", "sync", "create", "online"],
    warning: ["warning", "warn", "offline", "quota"],
    danger: ["error", "fail", "failed", "delete", "remove"],
  };

  function logLevel(type, message) {
    const text = `${type || ""} ${message || ""}`.toLowerCase();
    if (levelMap.danger.some((key) => text.includes(key))) return ["danger", "严重"];
    if (levelMap.warning.some((key) => text.includes(key))) return ["warning", "警告"];
    if (levelMap.success.some((key) => text.includes(key))) return ["success", "正常"];
    return ["info", "信息"];
  }

  document.querySelectorAll("[data-log-type]").forEach((node) => {
    const raw = node.dataset.logType || "";
    const key = raw.toLowerCase();
    node.textContent = labelMap[key] || raw || "未分类";
  });

  document.querySelectorAll("[data-log-level]").forEach((node) => {
    const row = node.closest("[data-log-row]");
    const type = row ? row.dataset.logType || "" : "";
    const message = row ? row.dataset.logMessage || "" : "";
    const [className, label] = logLevel(type, message);
    node.className = `badge ${className}`;
    node.textContent = label;
  });

  document.querySelectorAll("form[data-confirm]").forEach((form) => {
    form.addEventListener("submit", (event) => {
      const message = form.dataset.confirm || "确认执行该操作？";
      if (!window.confirm(message)) {
        event.preventDefault();
      }
    });
  });
})();

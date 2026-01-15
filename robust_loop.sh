#!/usr/bin/env bash
# Robust Feather Loop - 健壮版本，处理依赖问题

export HOME=/workspace
LOG_FILE="/tmp/feather_robust.log"

# 必要环境变量
export IFLOW_API_KEY="${IFLOW_API_KEY:-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}"
export IFLOW_BASE_URL="${IFLOW_BASE_URL:-https://integrate.api.nvidia.com/v1}"
export IFLOW_MODEL_NAME="${IFLOW_MODEL_NAME:-moonshotai/kimi-k2-thinking}"
export IFLOW_selectedAuthType="${IFLOW_selectedAuthType:-openai-compatible}"

cd /workspace/Feather

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

# 安装MoonBit (带重试和SSL绕过)
install_moon() {
  if command -v moon >/dev/null 2>&1; then
    log "Moon already installed: $(moon version 2>&1 | head -1)"
    return 0
  fi
  
  log "Attempting to install MoonBit..."
  
  # 尝试多种方法
  local attempts=0
  while [[ $attempts -lt 3 ]]; do
    attempts=$((attempts + 1))
    log "MoonBit install attempt ${attempts}..."
    
    # 方法1: 标准安装
    if curl -fsSL --insecure https://cli.moonbitlang.com/install/unix.sh 2>/dev/null | HOME=$HOME bash 2>/dev/null; then
      export PATH="$HOME/.moon/bin:$PATH"
      if command -v moon >/dev/null 2>&1; then
        log "MoonBit installed successfully"
        return 0
      fi
    fi
    
    sleep 5
  done
  
  log "WARNING: MoonBit installation failed, continuing without it"
  return 1
}

# 安装iflow
install_iflow() {
  if ! command -v iflow >/dev/null 2>&1; then
    log "Installing iFlow CLI..."
    npm i -g @iflow-ai/iflow-cli@latest 2>&1 | tee -a "$LOG_FILE" || log "iFlow installation had issues"
  fi
}

# Git配置
setup_git() {
  git config user.name "iflow-bot" 2>/dev/null || true
  git config user.email "iflow-bot@users.noreply.github.com" 2>/dev/null || true
}

# 推送更改
push_changes() {
  local msg="${1:-Auto update}"
  
  if ! git add -A 2>/dev/null; then
    log "ERROR: git add failed"
    return 1
  fi
  
  if git diff --cached --quiet 2>/dev/null; then
    log "No changes to commit"
    return 0
  fi
  
  if git commit -m "$msg" 2>/dev/null; then
    log "Committed changes"
    
    # 推送到Gitee
    if git remote get-url origin >/dev/null 2>&1; then
      if git push origin main 2>/dev/null; then
        log "Pushed to Gitee"
      else
        log "Failed to push to Gitee"
      fi
    fi
    
    # 推送到GitHub
    if git remote get-url github >/dev/null 2>&1; then
      if git push github main 2>/dev/null; then
        log "Pushed to GitHub"
      else
        log "Failed to push to GitHub"
      fi
    fi
  else
    log "Failed to commit"
  fi
}

# 主循环
main() {
  log "=========================================="
  log "Starting Robust Feather Loop"
  log "=========================================="
  
  setup_git
  install_iflow
  install_moon
  
  # 确保PATH包含moon
  export PATH="$HOME/.moon/bin:$PATH"
  
  log "PATH set to: $PATH"
  
  local loop_count=0
  
  while true; do
    loop_count=$((loop_count + 1))
    log "--- Loop #${loop_count} ---"
    
    # 检查moon是否可用
    if command -v moon >/dev/null 2>&1; then
      log "Running moon test..."
      if moon test 2>&1 | tee /tmp/moon_test.log; then
        log "Moon test passed"
        
        # 使用iflow增加测试
        if command -v iflow >/dev/null 2>&1; then
          log "Adding tests via iflow..."
          timeout 120 iflow "给这个项目增加一些moon test测试用例，不要超过10个 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow timeout or failed"
        fi
        
        push_changes "测试通过 - $(date '+%F %T')"
      else
        log "Moon test failed, attempting fix..."
        
        if command -v iflow >/dev/null 2>&1; then
          log "Fixing issues via iflow..."
          timeout 180 iflow "解决moon test显示的所有问题，只修改代码解决编译错误和运行时错误，尽量不要消耗大量资源 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow fix timeout or failed"
        fi
        
        push_changes "修复问题 - $(date '+%F %T')"
      fi
    else
      log "Moon not available, using alternative approach"
      
      # 即使没有moon，也尝试使用iflow改进代码
      if command -v iflow >/dev/null 2>&1; then
        log "Enhancing code via iflow..."
        timeout 180 iflow "改进这个MoonBit项目，实现PLAN.md中描述的功能，添加必要的测试用例 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow timeout or failed"
        
        push_changes "iflow更新 - $(date '+%F %T')"
      fi
    fi
    
    log "Loop #${loop_count} completed, sleeping..."
    sleep 10
  done
}

main "$@"

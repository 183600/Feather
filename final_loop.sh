#!/usr/bin/env bash
# Final Feather Loop - 最终版本，处理所有已知问题

export HOME=/workspace
export PATH="$HOME/.moon/bin:$PATH"
LOG_FILE="/tmp/feather_final.log"

# 必要环境变量
export IFLOW_API_KEY="${IFLOW_API_KEY:-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}"
export IFLOW_BASE_URL="${IFLOW_BASE_URL:-https://integrate.api.nvidia.com/v1}"
export IFLOW_MODEL_NAME="${IFLOW_MODEL_NAME:-moonshotai/kimi-k2-thinking}"
export IFLOW_selectedAuthType="${IFLOW_selectedAuthType:-openai-compatible}"

cd /workspace/Feather

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
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
    log "Committed: $msg"
    
    # 推送到Gitee
    if git remote get-url origin >/dev/null 2>&1; then
      if git push origin main 2>/dev/null; then
        log "✓ Pushed to Gitee"
      else
        log "✗ Failed to push to Gitee"
      fi
    fi
    
    # 推送到GitHub
    if git remote get-url github >/dev/null 2>&1; then
      if git push github main 2>/dev/null; then
        log "✓ Pushed to GitHub"
      else
        log "✗ Failed to push to GitHub"
      fi
    fi
  else
    log "✗ Failed to commit"
  fi
}

# 修复moon依赖问题
fix_moon_deps() {
  log "Attempting to fix MoonBit dependencies..."
  
  # 尝试重新安装依赖
  if moon install --directory=/workspace/Feather 2>&1 | tee -a "$LOG_FILE"; then
    log "Dependencies installed"
    return 0
  fi
  
  # 如果还是失败，使用iflow来修复
  log "Using iflow to fix dependency issues..."
  timeout 180 iflow "这个MoonBit项目的依赖解析失败，提示'Cannot inject the standard library moonbitlang/core'。请检查moon.mod.json和moon.pkg.json配置，修复依赖问题让项目能够正常编译和运行。只修改配置文件，不要删除现有功能。 think:high" --yolo >> "$LOG_FILE" 2>&1
  
  return 1
}

# 主循环
main() {
  log "🚀 Starting Final Feather Loop"
  log "Project: /workspace/Feather"
  
  setup_git
  
  # 确保iflow可用
  if ! command -v iflow >/dev/null 2>&1; then
    log "Installing iFlow CLI..."
    npm i -g @iflow-ai/iflow-cli@latest 2>&1 | tee -a "$LOG_FILE" || log "iFlow installation had issues"
  fi
  
  # 确保moon可用
  if ! command -v moon >/dev/null 2>&1; then
    log "Installing MoonBit..."
    curl -kfsSL https://cli.moonbitlang.com/install/unix.sh | HOME=$HOME bash 2>&1 | tee -a "$LOG_FILE"
    export PATH="$HOME/.moon/bin:$PATH"
  fi
  
  log "Environment ready"
  log "PATH: $PATH"
  
  local loop_count=0
  
  while true; do
    loop_count=$((loop_count + 1))
    log "=== Loop #${loop_count} ==="
    
    # 尝试运行moon test
    local moon_success=0
    if command -v moon >/dev/null 2>&1; then
      log "Running moon test..."
      
      # 先尝试安装依赖
      moon install --directory=/workspace/Feather >/dev/null 2>&1 || true
      
      if moon test --directory=/workspace/Feather 2>&1 | tee /tmp/moon_test.log; then
        log "✓ Moon test passed"
        moon_success=1
        
        # 使用iflow改进代码和测试
        log "Enhancing code with iflow..."
        timeout 120 iflow "Moon测试通过了！请给这个MoonBit Web框架项目(miniweb)增加一些新的测试用例来扩展测试覆盖范围，每个包(http, middleware, router, server)都添加2-3个测试，保持代码质量 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow timeout"
        
        push_changes "测试通过，添加测试用例 - $(date '+%F %T')"
      else
        log "✗ Moon test failed, attempting fix..."
        # 尝试修复依赖
        if fix_moon_deps; then
          log "Dependencies fixed, retrying test..."
          if moon test --directory=/workspace/Feather 2>&1 | tee /tmp/moon_test.log; then
            log "✓ Moon test passed after fix"
            moon_success=1
            push_changes "修复依赖后测试通过 - $(date '+%F %T')"
          fi
        fi
        
        if [[ $moon_success -eq 0 ]]; then
          log "Using iflow to fix build issues..."
          timeout 180 iflow "MoonBit项目编译/测试失败。请分析错误信息，修复src目录下所有包(http, middleware, router, server)中的代码问题，让项目能够正常编译和测试通过。只修复必要的代码，保持功能完整。 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow fix timeout"
          
          push_changes "修复编译问题 - $(date '+%F %T')"
        fi
      fi
    else
      log "Moon not available, using iflow directly..."
      timeout 180 iflow "请继续开发这个MoonBit Web框架项目(miniweb)，根据PLAN.md实现所有功能，添加必要的测试用例，修复任何问题。完成后提交代码。 think:high" --yolo >> "$LOG_FILE" 2>&1 || log "iflow timeout"
      
      push_changes "iflow更新代码 - $(date '+%F %T')"
    fi
    
    log "Loop #${loop_count} completed, sleeping 10s..."
    sleep 10
  done
}

main "$@"

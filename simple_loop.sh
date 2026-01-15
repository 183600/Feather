#!/usr/bin/env bash
# Simple Feather Loop - 核心功能简化版

export HOME=/workspace
export IFLOW_API_KEY="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"
export IFLOW_BASE_URL="https://integrate.api.nvidia.com/v1"
export IFLOW_MODEL_NAME="moonshotai/kimi-k2-thinking"
export IFLOW_selectedAuthType="openai-compatible"

cd /workspace/Feather

echo "[$(date '+%F %T')] Starting simple loop..."

loop_count=0
while true; do
  loop_count=$((loop_count + 1))
  echo "[$(date '+%F %T')] Loop #${loop_count} - Running moon test..."
  
  # 运行moon test
  if moon test 2>&1 | tee /tmp/moon_test_output.log; then
    echo "[$(date '+%F %T')] Moon test passed"
    
    # 使用iflow增加测试用例
    if command -v iflow >/dev/null 2>&1; then
      echo "[$(date '+%F %T')] Adding test cases via iflow..."
      iflow "给这个项目增加一些moon test测试用例，不要超过10个 think:high" --yolo || echo "[$(date '+%F %T')] iflow failed or no changes"
    fi
    
    # 提交更改
    if git add -A && git diff --cached --quiet; then
      echo "[$(date '+%F %T')] No changes to commit"
    else
      git commit -m "测试通过 - $(date '+%F %T')" || echo "[$(date '+%F %T')] Commit failed"
    fi
    
    # 推送到远端
    echo "[$(date '+%F %T')] Pushing to remotes..."
    git push origin main || echo "[$(date '+%F %T')] Push to origin failed"
    if git remote get-url github >/dev/null 2>&1; then
      git push github main || echo "[$(date '+%F %T')] Push to github failed"
    fi
  else
    echo "[$(date '+%F %T')] Moon test failed, fixing via iflow..."
    if command -v iflow >/dev/null 2>&1; then
      iflow "解决moon test显示的所有问题（除了warning），除非测试用例本身有编译错误，否则只修改测试用例以外的代码，debug时可通过加日志和打断点，尽量不要消耗大量CPU/内存资源 think:high" --yolo || echo "[$(date '+%F %T')] iflow fix failed"
    fi
  fi
  
  echo "[$(date '+%F %T')] Sleeping 5 seconds..."
  sleep 5
done

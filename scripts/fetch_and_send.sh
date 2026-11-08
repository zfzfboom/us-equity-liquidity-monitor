#!/bin/bash
set -e
set +e

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
TODAY=$(TZ=America/New_York date +'%Y-%m-%d')

fetch() {
  curl -s --max-time 12 -H "User-Agent: $UA" \
    "https://query1.finance.yahoo.com/v8/finance/chart/$1?interval=1d&range=5d" |
  python3 -c 'import sys,json
try:
  m=json.load(sys.stdin)["chart"]["result"][0]["meta"]
  print(m.get("regularMarketPrice") or "N/A", m.get("regularMarketChangePercent") or "N/A")
except: print("N/A", "N/A")'
}

read VIX VIX_CHG <<< "$(fetch %5EVIX)"
read VVIX VVIX_CHG <<< "$(fetch %5EVVIX)"
read SPX _ <<< "$(fetch %5EGSPC)"
read VIX9D VIX9D_CHG <<< "$(fetch %5EVIX9D)"
read VIX3M _ <<< "$(fetch %5EVIX3M)"
read SKEW SKEW_CHG <<< "$(fetch %5ESKEW)"

fmt() { [[ "$1" =~ ^-?[0-9] ]] && printf "%+.2f%%" "$1" || echo "N/A"; }
VIX_CHG_FMT=$(fmt "$VIX_CHG")
VVIX_CHG_FMT=$(fmt "$VVIX_CHG")
VIX9D_CHG_FMT=$(fmt "$VIX9D_CHG")
SKEW_CHG_FMT=$(fmt "$SKEW_CHG")

TERM="N/A"
if [[ "$VIX9D" =~ ^[0-9] && "$VIX" =~ ^[0-9] ]]; then
  if python3 -c "exit(0 if float('$VIX9D') > float('$VIX') else 1)"; then
    TERM="近端倒挂"
  else
    TERM="正常"
  fi
fi

# SKEW regime: ~100 normal, >135 elevated, >150 extreme tail pricing
SKEW_STATUS="N/A"
if [[ "$SKEW" =~ ^[0-9] ]]; then
  SKEW_STATUS=$(python3 -c "v=float('$SKEW')
print('极端' if v>=150 else ('走阔' if v>=135 else '正常'))")
fi

GEX=$(curl -s --max-time 10 "https://algoxflow.com/api/gexmap?ticker=SPY")
REGIME=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("regime","N/A"))' 2>/dev/null || echo N/A)
TOTAL_GEX=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("totalGex","N/A"))' 2>/dev/null || echo N/A)
CALL_WALL=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("callWall","N/A"))' 2>/dev/null || echo N/A)
PUT_WALL=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("putWall","N/A"))' 2>/dev/null || echo N/A)

SG=$(curl -s --max-time 10 "https://raw.githubusercontent.com/dhawalc/spx-gamma-levels/main/data/latest.json")
SPX_REGIME=$(echo "$SG" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("gamma_regime","N/A"))' 2>/dev/null || echo N/A)
SPX_FLIP=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("zero_gamma_flip"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_CALL=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("call_wall"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_PUT=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("put_wall"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_NET=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("net_gex_dollars"); print(f"{v/1e9:.1f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)

DAILY_FILE="daily/${TODAY}.md"
HAS_DAILY=0
[ -f "$DAILY_FILE" ] && HAS_DAILY=1

echo "VIX=$VIX VVIX=$VVIX SKEW=$SKEW TERM=$TERM SPX=$SPX daily=$HAS_DAILY"

{
  echo "📊 *美股流动性每日观测*"
  echo "📅 $TODAY"
  echo ""
  echo "*市场快照*"
  echo "• SPX：$SPX"
  echo "• VIX：$VIX  ($VIX_CHG_FMT)"
  echo "• VVIX：$VVIX  ($VVIX_CHG_FMT)"
  echo ""
  echo "*波动率期限结构*"
  echo "• VIX9D（近端）：$VIX9D  ($VIX9D_CHG_FMT)"
  echo "• VIX（30天）：$VIX"
  echo "• VIX3M（3个月）：$VIX3M"
  echo "• 结构状态：*$TERM*"
  echo ""
  echo "*Skew（自动）*"
  echo "• CBOE SKEW：$SKEW  ($SKEW_CHG_FMT)"
  echo "• 状态：*$SKEW_STATUS*  （≥150极端 / ≥135走阔 / 否则正常）"
  echo ""
  echo "*GEX 结构（自动）*"
  echo "• SPX Regime：*$SPX_REGIME*"
  echo "• Net GEX：${SPX_NET} Bn"
  echo "• Zero Gamma Flip：$SPX_FLIP"
  echo "• Call Wall：$SPX_CALL"
  echo "• Put Wall：$SPX_PUT"
  echo ""
  echo "• SPY Regime：$REGIME (GEX $TOTAL_GEX)"
  echo "• SPY Call/Put Wall：$CALL_WALL / $PUT_WALL"
  echo ""

  if [ "$HAS_DAILY" = "1" ]; then
    echo "*人工判断（已提交）*"
    STATUS=$(grep -E '综合状态|市场状态' "$DAILY_FILE" | head -1 | sed 's/.*[：:]//' | xargs || true)
    [ -n "$STATUS" ] && echo "• 综合状态：*$STATUS*"
    echo ""
    echo "*详细摘录*"
    tail -35 "$DAILY_FILE" | head -c 1200
    echo ""
    echo "——"
    echo "🔗 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/${TODAY}.md"
  else
    echo "⚠️ *待补充（盘口仍需人工）*"
    echo "1. 复制模板 → daily/${TODAY}.md"
    echo "2. 填写：买盘深度 / 价差 / 价格影响 / 跳空"
    echo "3. 提交后可手动 Run workflow 立即推送完整版"
    echo ""
    echo "📝 模板：https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/template.md"
    echo "📋 清单：https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/checklist/daily-checklist.md"
  fi
} > /tmp/msg.txt

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "Missing Telegram secrets"
  exit 1
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=$(cat /tmp/msg.txt)" \
  --data-urlencode "parse_mode=Markdown" \
  --data-urlencode "disable_web_page_preview=true"

echo "Message sent"

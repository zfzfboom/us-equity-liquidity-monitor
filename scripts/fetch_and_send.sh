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

fmt() { [[ "$1" =~ ^-?[0-9] ]] && printf "%+.2f%%" "$1" || echo "N/A"; }
VIX_CHG_FMT=$(fmt "$VIX_CHG")
VVIX_CHG_FMT=$(fmt "$VVIX_CHG")
VIX9D_CHG_FMT=$(fmt "$VIX9D_CHG")

TERM="N/A"
if [[ "$VIX9D" =~ ^[0-9] && "$VIX" =~ ^[0-9] ]]; then
  if python3 -c "exit(0 if float('$VIX9D') > float('$VIX') else 1)"; then
    TERM="近端倒挂"
  else
    TERM="正常"
  fi
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

echo "VIX=$VIX ($VIX_CHG_FMT) VVIX=$VVIX VIX9D=$VIX9D TERM=$TERM SPX=$SPX"

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
  echo "⚠️ 请补充 Skew / 盘口后提交 daily 文件"
  echo "📋 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/checklist/daily-checklist.md"
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

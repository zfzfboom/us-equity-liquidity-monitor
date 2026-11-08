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

SKEW_STATUS="N/A"
if [[ "$SKEW" =~ ^[0-9] ]]; then
  SKEW_STATUS=$(python3 -c "v=float('$SKEW'); print('极端' if v>=150 else ('走阔' if v>=135 else '正常'))")
fi

# ---- Free liquidity proxies from SPY 5m bars ----
LIQ_JSON=$(curl -s --max-time 15 -H "User-Agent: $UA" \
  "https://query1.finance.yahoo.com/v8/finance/chart/SPY?interval=5m&range=5d")

read RANGE_BPS MED_BPS HOUR_VOL LIQ_STATUS <<< "$(echo "$LIQ_JSON" | python3 -c '
import sys,json
try:
  d=json.load(sys.stdin)
  o=d["chart"]["result"][0]["indicators"]["quote"][0]
  n=12  # ~1 hour of 5m bars
  hs,ls,cs,vs=o["high"],o["low"],o["close"],o["volume"]
  ranges=[]
  for h,l,c in zip(hs,ls,cs):
    if h and l and c and c>0:
      ranges.append((h-l)/c*10000)
  recent=ranges[-n:] if len(ranges)>=n else ranges
  avg=sum(recent)/len(recent) if recent else None
  med=sorted(ranges)[len(ranges)//2] if ranges else None
  vol=sum((v or 0) for v in (vs[-n:] if len(vs)>=n else vs))
  status="N/A"
  if avg is not None and med is not None and med>0:
    ratio=avg/med
    if ratio>=1.8:
      status="放大/紧张"
    elif ratio>=1.3:
      status="偏阔"
    else:
      status="正常"
  def f(x):
    return f"{x:.1f}" if isinstance(x,(int,float)) else "N/A"
  print(f(avg), f(med), int(vol) if vol else "N/A", status)
except Exception:
  print("N/A", "N/A", "N/A", "N/A")
' 2>/dev/null || echo "N/A N/A N/A N/A")

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

echo "VIX=$VIX SKEW=$SKEW TERM=$TERM LIQ=$LIQ_STATUS RANGE=$RANGE_BPS SPX=$SPX"

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
  echo "• 状态：*$SKEW_STATUS*"
  echo ""
  echo "*盘口代理（SPY 5分钟免费估算）*"
  echo "• 近1小时均波幅：${RANGE_BPS} bps"
  echo "• 当日中位波幅：${MED_BPS} bps"
  echo "• 近1小时成交量：${HOUR_VOL}"
  echo "• 流动性状态：*$LIQ_STATUS*"
  echo "• 说明：非L2真盘口，用波幅相对中位数代理价差/冲击"
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
    tail -35 "$DAILY_FILE" | head -c 1000
    echo ""
    echo "——"
    echo "🔗 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/${TODAY}.md"
  else
    echo "⚠️ 如需更精确盘口（真深度/跳空），请补 daily/${TODAY}.md 后手动 Run"
    echo "📝 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/template.md"
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

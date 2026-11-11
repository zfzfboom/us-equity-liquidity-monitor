#!/bin/bash
set +e

UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

# 从 Yahoo 日线数据中提取真实最后交易日（避免 GitHub 延迟导致日期显示落后一天）
get_data_date() {
  curl -s --max-time 12 -H "User-Agent: $UA" \
    "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?interval=1d&range=5d" |
  python3 -c '
import sys, json
from datetime import datetime, timezone
try:
  r = json.load(sys.stdin)["chart"]["result"][0]
  ts = r["timestamp"][-1]
  # Yahoo timestamp is Unix seconds (UTC)
  dt = datetime.fromtimestamp(ts, tz=timezone.utc)
  # 美东日期（考虑夏令时用固定偏移近似，足够用于标签）
  print(dt.strftime("%Y-%m-%d"))
except Exception:
  print("unknown")
'
}

TODAY=$(get_data_date)
if [ "$TODAY" = "unknown" ] || [ -z "$TODAY" ]; then
  TODAY=$(TZ=America/New_York date +%Y-%m-%d)
fi

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

fmt() { [[ "$1" =~ ^-?[0-9] ]] && printf '%+.2f%%' "$1" || echo 'N/A'; }
VIX_CHG_FMT=$(fmt "$VIX_CHG")
VVIX_CHG_FMT=$(fmt "$VVIX_CHG")
VIX9D_CHG_FMT=$(fmt "$VIX9D_CHG")
SKEW_CHG_FMT=$(fmt "$SKEW_CHG")

TERM='N/A'
if [[ "$VIX9D" =~ ^[0-9] && "$VIX" =~ ^[0-9] ]]; then
  if python3 -c "exit(0 if float('$VIX9D') > float('$VIX') else 1)"; then
    TERM='近端倒挂'
  else
    TERM='正常'
  fi
fi

SKEW_STATUS='N/A'
if [[ "$SKEW" =~ ^[0-9] ]]; then
  SKEW_STATUS=$(python3 -c "v=float('$SKEW'); print('极端' if v>=150 else ('走阔' if v>=135 else '正常'))")
fi

# SPY 5m liquidity proxy
curl -s --max-time 15 -H "User-Agent: $UA" \
  'https://query1.finance.yahoo.com/v8/finance/chart/SPY?interval=5m&range=5d' > /tmp/spy5m.json

RANGE_BPS=$(python3 - <<'PY'
import json
try:
  d=json.load(open('/tmp/spy5m.json'))
  o=d['chart']['result'][0]['indicators']['quote'][0]
  n=12
  ranges=[]
  for h,l,c in zip(o['high'],o['low'],o['close']):
    if h and l and c and c>0:
      ranges.append((h-l)/c*10000)
  recent=ranges[-n:] if len(ranges)>=n else ranges
  avg=sum(recent)/len(recent) if recent else None
  print(f'{avg:.1f}' if avg is not None else 'N/A')
except Exception:
  print('N/A')
PY
)

MED_BPS=$(python3 - <<'PY'
import json
try:
  d=json.load(open('/tmp/spy5m.json'))
  o=d['chart']['result'][0]['indicators']['quote'][0]
  ranges=[]
  for h,l,c in zip(o['high'],o['low'],o['close']):
    if h and l and c and c>0:
      ranges.append((h-l)/c*10000)
  med=sorted(ranges)[len(ranges)//2] if ranges else None
  print(f'{med:.1f}' if med is not None else 'N/A')
except Exception:
  print('N/A')
PY
)

HOUR_VOL=$(python3 - <<'PY'
import json
try:
  d=json.load(open('/tmp/spy5m.json'))
  vs=d['chart']['result'][0]['indicators']['quote'][0]['volume']
  n=12
  vol=sum((v or 0) for v in (vs[-n:] if len(vs)>=n else vs))
  print(int(vol))
except Exception:
  print('N/A')
PY
)

LIQ_STATUS=$(python3 - <<PY
try:
  avg=float('$RANGE_BPS'); med=float('$MED_BPS')
  ratio=avg/med if med>0 else 0
  print('放大/紧张' if ratio>=1.8 else ('偏阔' if ratio>=1.3 else '正常'))
except Exception:
  print('N/A')
PY
)

GEX=$(curl -s --max-time 10 'https://algoxflow.com/api/gexmap?ticker=SPY')
REGIME=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("regime","N/A"))' 2>/dev/null || echo N/A)
TOTAL_GEX=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("totalGex","N/A"))' 2>/dev/null || echo N/A)
CALL_WALL=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("callWall","N/A"))' 2>/dev/null || echo N/A)
PUT_WALL=$(echo "$GEX" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("putWall","N/A"))' 2>/dev/null || echo N/A)

SG=$(curl -s --max-time 10 'https://raw.githubusercontent.com/dhawalc/spx-gamma-levels/main/data/latest.json')
SPX_REGIME=$(echo "$SG" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("gamma_regime","N/A"))' 2>/dev/null || echo N/A)
SPX_FLIP=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("zero_gamma_flip"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_CALL=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("call_wall"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_PUT=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("put_wall"); print(f"{v:.0f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)
SPX_NET=$(echo "$SG" | python3 -c 'import sys,json; v=json.load(sys.stdin).get("net_gex_dollars"); print(f"{v/1e9:.1f}" if isinstance(v,(int,float)) else "N/A")' 2>/dev/null || echo N/A)

DAILY_FILE="daily/${TODAY}.md"
HAS_DAILY=0
[ -f "$DAILY_FILE" ] && HAS_DAILY=1

echo "DATA_DATE=$TODAY VIX=$VIX SKEW=$SKEW TERM=$TERM LIQ=$LIQ_STATUS RANGE=$RANGE_BPS SPX=$SPX"

cat > /tmp/msg.txt << EOF
📊 *美股流动性每日观测*
📅 ${TODAY}

*市场快照*
• SPX：${SPX}
• VIX：${VIX}  (${VIX_CHG_FMT})
• VVIX：${VVIX}  (${VVIX_CHG_FMT})

*波动率期限结构*
• VIX9D（近端）：${VIX9D}  (${VIX9D_CHG_FMT})
• VIX（30天）：${VIX}
• VIX3M（3个月）：${VIX3M}
• 结构状态：*${TERM}*

*Skew（自动）*
• CBOE SKEW：${SKEW}  (${SKEW_CHG_FMT})
• 状态：*${SKEW_STATUS}*

*盘口代理（SPY 5分钟免费估算）*
• 近1小时均波幅：${RANGE_BPS} bps
• 当日中位波幅：${MED_BPS} bps
• 近1小时成交量：${HOUR_VOL}
• 流动性状态：*${LIQ_STATUS}*
• 说明：非L2真盘口，用波幅相对中位数代理价差/冲击

*GEX 结构（自动）*
• SPX Regime：*${SPX_REGIME}*
• Net GEX：${SPX_NET} Bn
• Zero Gamma Flip：${SPX_FLIP}
• Call Wall：${SPX_CALL}
• Put Wall：${SPX_PUT}

• SPY Regime：${REGIME} (GEX ${TOTAL_GEX})
• SPY Call/Put Wall：${CALL_WALL} / ${PUT_WALL}
EOF

if [ "$HAS_DAILY" = "1" ]; then
  echo "" >> /tmp/msg.txt
  echo "*人工判断已提交*" >> /tmp/msg.txt
  echo "🔗 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/${TODAY}.md" >> /tmp/msg.txt
else
  echo "" >> /tmp/msg.txt
  echo "⚠️ 真深度/跳空仍建议人工补 daily 文件" >> /tmp/msg.txt
  echo "📝 https://github.com/zfzfboom/us-equity-liquidity-monitor/blob/main/daily/template.md" >> /tmp/msg.txt
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo 'Missing Telegram secrets'
  exit 1
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=$(cat /tmp/msg.txt)" \
  --data-urlencode 'parse_mode=Markdown' \
  --data-urlencode 'disable_web_page_preview=true'

echo 'Message sent'

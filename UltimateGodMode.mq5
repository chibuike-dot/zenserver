//+------------------------------------------------------------------+
//| ULTIMATE v6 GOD MODE EA - Full ICT/SMC Confluence                |
//| Converted from Pine Script to MQL5                               |
//+------------------------------------------------------------------+
#property copyright "Converted from Pine Script"
#property version   "6.00"
#property strict

// Input Parameters
input group "=== Core Settings ==="
input bool   ShowGodMode     = true;
input bool   ShowStrong      = true;
input bool   ShowModerate    = true;
input int    GodThreshold    = 95;
input int    StrongThreshold = 85;
input int    ModThreshold    = 70;

input group "=== ICT/SMC Modules ==="
input bool   UseOrderBlocks   = true;
input bool   UseFVG           = true;
input bool   UseBreaker       = true;
input bool   UseUnicorn       = true;
input bool   UseLiqSweep      = true;
input bool   UseOTE           = true;
input bool   UseBPR           = true;
input bool   UseInducement    = true;
input bool   UseMSS           = true;
input bool   UseKillZones     = true;

input group "=== Classical TA ==="
input bool   UseEngulfing     = true;
input bool   UseHammer        = true;
input bool   UseMorningStar   = true;
input bool   UseDoji          = true;
input bool   UseRegDiv        = true;
input bool   UseHidDiv        = true;
input bool   UseBBSqueeze     = true;
input bool   UseSupertrend    = true;
input bool   UseEMARibbon     = true;
input bool   UseIchimoku      = true;

input group "=== Volume ==="
input bool   UseVolDelta      = true;
input bool   UsePOCRej        = true;

input group "=== Multi-Timeframe ==="
input ENUM_TIMEFRAMES HTF1    = PERIOD_H1;
input ENUM_TIMEFRAMES HTF2    = PERIOD_H4;
input ENUM_TIMEFRAMES HTF3    = PERIOD_D1;
input bool   UseHTF1          = true;
input bool   UseHTF2          = true;
input bool   UseHTF3          = true;

input group "=== Trade Management ==="
input double RiskPercent      = 1.0;
input double ATR_SL_Mult      = 1.5;
input double ATR_TP1_Mult     = 2.0;
input double ATR_TP2_Mult     = 3.0;
input double ATR_TP3_Mult     = 4.0;
input int    MaxTrades        = 3;
input bool   UseTrailingStop  = true;
input double TrailATRMult     = 1.0;

input group "=== Session Filters ==="
input bool   FilterSessions   = false;
input string AsianSession     = "00:00-02:00";
input string LondonSession    = "02:00-05:00";
input string NYSession        = "08:30-12:00";

input group "=== Pivot Settings ==="
input int    PivotLookback    = 5;

// Global Variables
int    structTrend    = 0;
double lastSwingHigh  = 0;
double lastSwingLow   = 0;
int    lastSwingHighBar = 0;
int    lastSwingLowBar  = 0;
double prevSwingHigh  = 0;
double prevSwingLow   = 0;

// Order Block Storage
struct OBZone {
   double top;
   double bot;
   int    startBar;
   bool   mitigated;
};

struct FVGZone {
   double top;
   double bot;
   int    startBar;
   bool   bullish;
   bool   filled;
};

OBZone  bullOBs[];
OBZone  bearOBs[];
FVGZone fvgZones[];

int MAX_OB  = 8;
int MAX_FVG = 12;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(bullOBs,  0);
   ArrayResize(bearOBs,  0);
   ArrayResize(fvgZones, 0);
   Print("ULTIMATE GOD MODE EA v6 Initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper Functions                                                  |
//+------------------------------------------------------------------+
double GetATR(int period, int shift=0)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(iATR(_Symbol, PERIOD_CURRENT, period), 0, shift, 1, atr) > 0)
      return atr[0];
   return 0;
}

double GetRSI(int period, int shift=0)
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(iRSI(_Symbol, PERIOD_CURRENT, period, PRICE_CLOSE), 0, shift, 1, rsi) > 0)
      return rsi[0];
   return 50;
}

double GetEMA(int period, int shift=0)
{
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(iMA(_Symbol, PERIOD_CURRENT, period, 0, MODE_EMA, PRICE_CLOSE), 0, shift, 1, ema) > 0)
      return ema[0];
   return 0;
}

double GetStoch(int period, int shift=0)
{
   double stoch[];
   ArraySetAsSeries(stoch, true);
   if(CopyBuffer(iStochastic(_Symbol, PERIOD_CURRENT, period, 3, 3, MODE_SMA, STO_LOWHIGH), 0, shift, 1, stoch) > 0)
      return stoch[0];
   return 50;
}

double GetVolume(int shift=0)
{
   long vol[];
   ArraySetAsSeries(vol, true);
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, shift, 1, vol) > 0)
      return (double)vol[0];
   return 0;
}

double GetHTFClose(ENUM_TIMEFRAMES tf, int shift=1)
{
   double c[];
   ArraySetAsSeries(c, true);
   if(CopyClose(_Symbol, tf, shift, 1, c) > 0) return c[0];
   return 0;
}

double GetHTFOpen(ENUM_TIMEFRAMES tf, int shift=1)
{
   double o[];
   ArraySetAsSeries(o, true);
   if(CopyOpen(_Symbol, tf, shift, 1, o) > 0) return o[0];
   return 0;
}

int GetHTFBias(ENUM_TIMEFRAMES tf)
{
   double c = GetHTFClose(tf);
   double o = GetHTFOpen(tf);
   if(c > o) return 1;
   if(c < o) return -1;
   return 0;
}

bool InSession(string sessionStr)
{
   string parts[];
   if(StringSplit(sessionStr, '-', parts) == 2)
   {
      datetime sessionStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + parts[0]);
      datetime sessionEnd   = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " " + parts[1]);
      datetime now          = TimeCurrent();
      return(now >= sessionStart && now <= sessionEnd);
   }
   return false;
}

bool InKillZone()
{
   return InSession(AsianSession) || InSession(LondonSession) || InSession(NYSession);
}

double GetPivotHigh(int lookback, int shift)
{
   double highs[];
   ArraySetAsSeries(highs, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, lookback*2+shift+1, highs) <= 0) return 0;
   double centerHigh = highs[lookback+shift];
   for(int i = 0; i < lookback*2+1; i++)
   {
      if(i == lookback) continue;
      if(highs[i+shift] >= centerHigh) return 0;
   }
   return centerHigh;
}

double GetPivotLow(int lookback, int shift)
{
   double lows[];
   ArraySetAsSeries(lows, true);
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, lookback*2+shift+1, lows) <= 0) return 0;
   double centerLow = lows[lookback+shift];
   for(int i = 0; i < lookback*2+1; i++)
   {
      if(i == lookback) continue;
      if(lows[i+shift] <= centerLow) return 0;
   }
   return centerLow;
}

//+------------------------------------------------------------------+
//| Get price arrays                                                  |
//+------------------------------------------------------------------+
bool GetPriceArrays(double &opens[], double &highs[], double &lows[], double &closes[], int count)
{
   ArraySetAsSeries(opens,  true);
   ArraySetAsSeries(highs,  true);
   ArraySetAsSeries(lows,   true);
   ArraySetAsSeries(closes, true);
   return(CopyOpen(_Symbol,  PERIOD_CURRENT, 0, count, opens)  == count &&
          CopyHigh(_Symbol,  PERIOD_CURRENT, 0, count, highs)  == count &&
          CopyLow(_Symbol,   PERIOD_CURRENT, 0, count, lows)   == count &&
          CopyClose(_Symbol, PERIOD_CURRENT, 0, count, closes) == count);
}

//+------------------------------------------------------------------+
//| Calculate Confluence Score                                        |
//+------------------------------------------------------------------+
void CalculateScore(double &bullScore, double &bearScore)
{
   bullScore = 0;
   bearScore = 0;

   double opens[], highs[], lows[], closes[];
   int    count = 60;
   if(!GetPriceArrays(opens, highs, lows, closes, count)) return;

   double atr14 = GetATR(14);
   if(atr14 == 0) return;

   // ── Pivot Detection ──
   double pivHigh = GetPivotHigh(PivotLookback, PivotLookback);
   double pivLow  = GetPivotLow(PivotLookback,  PivotLookback);

   if(pivHigh > 0) { lastSwingHigh = pivHigh; lastSwingHighBar = PivotLookback; }
   if(pivLow  > 0) { lastSwingLow  = pivLow;  lastSwingLowBar  = PivotLookback; }

   // ── BOS / CHoCH / MSS ──
   bool bosUp    = false, bosDown   = false;
   bool chochUp  = false, chochDown = false;

   if(pivHigh > 0 && prevSwingHigh > 0)
   {
      if(pivHigh > prevSwingHigh) { chochUp  = (structTrend != 1);  bosUp   = (structTrend == 1);  structTrend = 1;  }
   }
   if(pivLow > 0 && prevSwingLow > 0)
   {
      if(pivLow < prevSwingLow)  { chochDown = (structTrend != -1); bosDown = (structTrend == -1); structTrend = -1; }
   }
   if(pivHigh > 0) prevSwingHigh = pivHigh;
   if(pivLow  > 0) prevSwingLow  = pivLow;

   bool mssUp   = chochUp;
   bool mssDown = chochDown;

   // ── Order Blocks ──
   if(bosUp || chochUp)
   {
      for(int i = 1; i < 15 && i < count; i++)
      {
         if(closes[i] < opens[i])
         {
            OBZone ob;
            ob.top       = MathMax(opens[i], closes[i]);
            ob.bot       = MathMin(opens[i], closes[i]);
            ob.startBar  = i;
            ob.mitigated = false;
            int sz = ArraySize(bullOBs);
            ArrayResize(bullOBs, sz+1);
            for(int j = sz; j > 0; j--) bullOBs[j] = bullOBs[j-1];
            bullOBs[0] = ob;
            if(ArraySize(bullOBs) > MAX_OB) ArrayResize(bullOBs, MAX_OB);
            break;
         }
      }
   }
   if(bosDown || chochDown)
   {
      for(int i = 1; i < 15 && i < count; i++)
      {
         if(closes[i] > opens[i])
         {
            OBZone ob;
            ob.top       = MathMax(opens[i], closes[i]);
            ob.bot       = MathMin(opens[i], closes[i]);
            ob.startBar  = i;
            ob.mitigated = false;
            int sz = ArraySize(bearOBs);
            ArrayResize(bearOBs, sz+1);
            for(int j = sz; j > 0; j--) bearOBs[j] = bearOBs[j-1];
            bearOBs[0] = ob;
            if(ArraySize(bearOBs) > MAX_OB) ArrayResize(bearOBs, MAX_OB);
            break;
         }
      }
   }

   // ── Mitigation ──
   for(int i = 0; i < ArraySize(bullOBs); i++)
      if(!bullOBs[i].mitigated && closes[0] < bullOBs[i].bot) bullOBs[i].mitigated = true;
   for(int i = 0; i < ArraySize(bearOBs); i++)
      if(!bearOBs[i].mitigated && closes[0] > bearOBs[i].top) bearOBs[i].mitigated = true;

   // ── OB Retest ──
   bool bullOBRetest = false, bearOBRetest = false;
   for(int i = 0; i < ArraySize(bullOBs); i++)
      if(!bullOBs[i].mitigated && lows[0] <= bullOBs[i].top && lows[0] >= bullOBs[i].bot && closes[0] > bullOBs[i].bot)
         bullOBRetest = true;
   for(int i = 0; i < ArraySize(bearOBs); i++)
      if(!bearOBs[i].mitigated && highs[0] >= bearOBs[i].bot && highs[0] <= bearOBs[i].top && closes[0] < bearOBs[i].top)
         bearOBRetest = true;

   // ── FVG Detection ──
   bool fvgBullDetect = (count >= 4) && (lows[1] > highs[3]);
   bool fvgBearDetect = (count >= 4) && (highs[1] < lows[3]);

   if(fvgBullDetect)
   {
      FVGZone fvg;
      fvg.top = lows[1]; fvg.bot = highs[3]; fvg.startBar = 1; fvg.bullish = true; fvg.filled = false;
      if(fvg.top > fvg.bot)
      {
         int sz = ArraySize(fvgZones);
         ArrayResize(fvgZones, sz+1);
         for(int j = sz; j > 0; j--) fvgZones[j] = fvgZones[j-1];
         fvgZones[0] = fvg;
         if(ArraySize(fvgZones) > MAX_FVG) ArrayResize(fvgZones, MAX_FVG);
      }
   }
   if(fvgBearDetect)
   {
      FVGZone fvg;
      fvg.top = lows[3]; fvg.bot = highs[1]; fvg.startBar = 1; fvg.bullish = false; fvg.filled = false;
      if(fvg.top > fvg.bot)
      {
         int sz = ArraySize(fvgZones);
         ArrayResize(fvgZones, sz+1);
         for(int j = sz; j > 0; j--) fvgZones[j] = fvgZones[j-1];
         fvgZones[0] = fvg;
         if(ArraySize(fvgZones) > MAX_FVG) ArrayResize(fvgZones, MAX_FVG);
      }
   }

   // ── FVG Fill Check ──
   for(int i = 0; i < ArraySize(fvgZones); i++)
   {
      if(!fvgZones[i].filled)
      {
         if(fvgZones[i].bullish && lows[0] <= fvgZones[i].top)  fvgZones[i].filled = true;
         if(!fvgZones[i].bullish && highs[0] >= fvgZones[i].bot) fvgZones[i].filled = true;
      }
   }

   // ── FVG Entry ──
   bool bullFVGEntry = false, bearFVGEntry = false;
   for(int i = 0; i < ArraySize(fvgZones); i++)
   {
      if(!fvgZones[i].filled)
      {
         if(fvgZones[i].bullish && lows[0] <= fvgZones[i].top && lows[0] >= fvgZones[i].bot && closes[0] > fvgZones[i].bot)
            bullFVGEntry = true;
         if(!fvgZones[i].bullish && highs[0] >= fvgZones[i].bot && highs[0] <= fvgZones[i].top && closes[0] < fvgZones[i].top)
            bearFVGEntry = true;
      }
   }

   // ── Breaker Blocks ──
   bool bullBreakerRetest = false, bearBreakerRetest = false;
   for(int i = 0; i < ArraySize(bullOBs); i++)
      if(bullOBs[i].mitigated && highs[0] >= bullOBs[i].bot && highs[0] <= bullOBs[i].top && closes[0] < bullOBs[i].bot)
         bearBreakerRetest = true;
   for(int i = 0; i < ArraySize(bearOBs); i++)
      if(bearOBs[i].mitigated && lows[0] <= bearOBs[i].top && lows[0] >= bearOBs[i].bot && closes[0] > bearOBs[i].top)
         bullBreakerRetest = true;

   // ── Unicorn ──
   bool bullUnicorn = bullFVGEntry && bullBreakerRetest;
   bool bearUnicorn = bearFVGEntry && bearBreakerRetest;

   // ── Liquidity Sweep + BOS ──
   bool liqSweepBull = (lastSwingLow > 0) && (lows[1] < lastSwingLow) && (closes[0] > lastSwingLow) && bosUp;
   bool liqSweepBear = (lastSwingHigh > 0) && (highs[1] > lastSwingHigh) && (closes[0] < lastSwingHigh) && bosDown;

   // ── OTE Fib ──
   bool oteBull = false, oteBear = false;
   if(lastSwingHigh > 0 && lastSwingLow > 0 && lastSwingHigh > lastSwingLow)
   {
      double rng          = lastSwingHigh - lastSwingLow;
      double oteBullTop   = lastSwingHigh - 0.618 * rng;
      double oteBullBot   = lastSwingHigh - 0.786 * rng;
      double oteBearTop   = lastSwingLow  + 0.786 * rng;
      double oteBearBot   = lastSwingLow  + 0.618 * rng;
      oteBull = (lows[0] <= oteBullTop && lows[0] >= oteBullBot && structTrend == 1);
      oteBear = (highs[0] >= oteBearBot && highs[0] <= oteBearTop && structTrend == -1);
   }

   // ── BPR ──
   bool bprBullRetest = false, bprBearRetest = false;
   if(ArraySize(fvgZones) >= 2)
   {
      double overlapTop = MathMin(fvgZones[0].top, fvgZones[1].top);
      double overlapBot = MathMax(fvgZones[0].bot, fvgZones[1].bot);
      if(overlapTop > overlapBot && fvgZones[0].bullish != fvgZones[1].bullish)
      {
         bprBullRetest = (lows[0] <= overlapTop && lows[0] >= overlapBot && structTrend == 1);
         bprBearRetest = (highs[0] >= overlapBot && highs[0] <= overlapTop && structTrend == -1);
      }
   }

   // ── Displacement / Inducement ──
   bool displacementUp   = false, displacementDown = false;
   if(count >= 5)
   {
      double eqLow  = (MathAbs(lows[2]  - lows[4])  < _Point * 5) ? lows[2]  : 0;
      double eqHigh = (MathAbs(highs[2] - highs[4]) < _Point * 5) ? highs[2] : 0;
      if(eqLow  > 0) displacementUp   = (lows[1] < eqLow  && closes[0] > eqLow  && (closes[0] - opens[0]) > (highs[1] - lows[1]) * 0.6);
      if(eqHigh > 0) displacementDown = (highs[1] > eqHigh && closes[0] < eqHigh && (opens[0] - closes[0]) > (highs[1] - lows[1]) * 0.6);
   }

   // ── Kill Zone Liquidity ──
   bool kzBull = InKillZone() && liqSweepBull;
   bool kzBear = InKillZone() && liqSweepBear;

   // ── Volume Delta ──
   double vol0    = GetVolume(0);
   double volMA   = 0;
   for(int i = 1; i <= 20; i++) volMA += GetVolume(i);
   volMA /= 20.0;

   double candleRange0 = highs[0] - lows[0];
   double buyVol0  = (candleRange0 > 0) ? vol0 * (closes[0] > opens[0] ? 1.0 : (closes[0] - lows[0]) / candleRange0) : vol0 * 0.5;
   double sellVol0 = vol0 - buyVol0;
   double delta0   = buyVol0 - sellVol0;

   double deltaMA = 0;
   for(int i = 1; i <= 14; i++)
   {
      double voli = GetVolume(i);
      double ri   = highs[i] - lows[i];
      double bv   = (ri > 0) ? voli * (closes[i] > opens[i] ? 1.0 : (closes[i] - lows[i]) / ri) : voli * 0.5;
      deltaMA += (bv - (voli - bv));
   }
   deltaMA /= 14.0;

   bool imbalanceBull = (delta0 > deltaMA * 1.5 && vol0 > volMA * 1.8);
   bool imbalanceBear = (delta0 < deltaMA * -1.5 && vol0 > volMA * 1.8);
   bool posVolDelta   = (delta0 > deltaMA && delta0 > 0) && (bullFVGEntry || bullOBRetest);
   bool negVolDelta   = (delta0 < deltaMA && delta0 < 0) && (bearFVGEntry || bearOBRetest);

   // ── VWAP / POC ──
   double vwap = (highs[0] + lows[0] + closes[0]) / 3.0;
   bool pocBull = (lows[1] <= vwap && closes[0] > vwap && structTrend == 1);
   bool pocBear = (highs[1] >= vwap && closes[0] < vwap && structTrend == -1);

   // ── RSI Divergence ──
   double rsi0 = GetRSI(14, 0);
   double rsi1 = GetRSI(14, PivotLookback);
   bool regBullDiv = (pivLow > 0 && lastSwingLow > 0 && pivLow < lastSwingLow && rsi0 > rsi1);
   bool regBearDiv = (pivHigh > 0 && lastSwingHigh > 0 && pivHigh > lastSwingHigh && rsi0 < rsi1);
   bool hidBullDiv = (pivLow > 0 && lastSwingLow > 0 && pivLow > lastSwingLow && rsi0 < rsi1);
   bool hidBearDiv = (pivHigh > 0 && lastSwingHigh > 0 && pivHigh < lastSwingHigh && rsi0 > rsi1);

   double stoch0 = GetStoch(14, 0);
   double stoch1 = GetStoch(14, PivotLookback);
   bool multiRegBullDiv = regBullDiv && (stoch0 > stoch1);
   bool multiRegBearDiv = regBearDiv && (stoch0 < stoch1);

   // ── EMA Ribbon ──
   double ema8  = GetEMA(8);
   double ema13 = GetEMA(13);
   double ema21 = GetEMA(21);
   double ema34 = GetEMA(34);
   double ema55 = GetEMA(55);

   bool emaRibbonBull = (ema8 > ema13 && ema13 > ema21 && ema21 > ema34 && ema34 > ema55);
   bool emaRibbonBear = (ema8 < ema13 && ema13 < ema21 && ema21 < ema34 && ema34 < ema55);
   bool emaPullBull   = emaRibbonBull && lows[0] <= ema21 && closes[0] > ema21 && structTrend == 1;
   bool emaPullBear   = emaRibbonBear && highs[0] >= ema21 && closes[0] < ema21 && structTrend == -1;

   // ── BB Squeeze ──
   double bbBasis = 0;
   for(int i = 0; i < 20; i++) bbBasis += closes[i];
   bbBasis /= 20.0;
   double bbDev = 0;
   for(int i = 0; i < 20; i++) bbDev += MathPow(closes[i] - bbBasis, 2);
   bbDev = MathSqrt(bbDev / 20.0);
   double bbUpper = bbBasis + 2.0 * bbDev;
   double bbLower = bbBasis - 2.0 * bbDev;
   double bbWidth = bbUpper - bbLower;
   double bbWidthMA = 0;
   for(int i = 0; i < 20; i++)
   {
      double basisI = 0;
      for(int j = i; j < i+20; j++) basisI += closes[j];
      basisI /= 20.0;
      double devI = 0;
      for(int j = i; j < i+20; j++) devI += MathPow(closes[j] - basisI, 2);
      devI = MathSqrt(devI / 20.0);
      bbWidthMA += (basisI + 2*devI) - (basisI - 2*devI);
   }
   bbWidthMA /= 20.0;
   bool bbSqueeze    = (bbWidth < bbWidthMA * 0.7);
   bool bbBreakupUp  = bbSqueeze && closes[0] > bbUpper && emaRibbonBull;
   bool bbBreakupDn  = bbSqueeze && closes[0] < bbLower && emaRibbonBear;

   // ── Supertrend ──
   double atr10 = GetATR(10);
   double stUpper = (highs[0] + lows[0]) / 2.0 - 3.0 * atr10;
   double stLower = (highs[0] + lows[0]) / 2.0 + 3.0 * atr10;
   bool stFlipUp   = (closes[0] > stUpper && closes[1] <= stUpper);
   bool stFlipDown = (closes[0] < stLower && closes[1] >= stLower);
   bool stOBBull   = stFlipUp   && bullOBRetest;
   bool stOBBear   = stFlipDown && bearOBRetest;

   // ── Ichimoku ──
   double convHigh = 0, convLow = 999999;
   for(int i = 0; i < 9;  i++) { if(highs[i] > convHigh) convHigh = highs[i]; if(lows[i] < convLow) convLow = lows[i]; }
   double baseHigh = 0, baseLow = 999999;
   for(int i = 0; i < 26; i++) { if(highs[i] > baseHigh) baseHigh = highs[i]; if(lows[i] < baseLow) baseLow = lows[i]; }
   double ichiConv = (convHigh + convLow) / 2.0;
   double ichiBase = (baseHigh + baseLow) / 2.0;
   double prevConvHigh = 0, prevConvLow = 999999;
   for(int i = 1; i < 10; i++) { if(highs[i] > prevConvHigh) prevConvHigh = highs[i]; if(lows[i] < prevConvLow) prevConvLow = lows[i]; }
   double prevBaseHigh = 0, prevBaseLow = 999999;
   for(int i = 1; i < 27; i++) { if(highs[i] > prevBaseHigh) prevBaseHigh = highs[i]; if(lows[i] < prevBaseLow) prevBaseLow = lows[i]; }
   double prevConv = (prevConvHigh + prevConvLow) / 2.0;
   double prevBase = (prevBaseHigh + prevBaseLow) / 2.0;
   double ichiLeadA = (ichiConv + ichiBase) / 2.0;
   double lead52High = 0, lead52Low = 999999;
   for(int i = 0; i < 52; i++) { if(highs[i] > lead52High) lead52High = highs[i]; if(lows[i] < lead52Low) lead52Low = lows[i]; }
   double ichiLeadB  = (lead52High + lead52Low) / 2.0;
   bool tkCrossUp    = (prevConv < prevBase && ichiConv > ichiBase);
   bool tkCrossDown  = (prevConv > prevBase && ichiConv < ichiBase);
   bool cloudBull    = (ichiLeadA > ichiLeadB);
   bool cloudBear    = (ichiLeadA < ichiLeadB);
   bool ichiBreakBull = tkCrossUp   && cloudBull && closes[0] > MathMax(ichiLeadA, ichiLeadB);
   bool ichiBreakBear = tkCrossDown && cloudBear && closes[0] < MathMin(ichiLeadA, ichiLeadB);

   // ── Candle Patterns ──
   bool bullEngulf = (closes[1] > opens[1] && closes[2] < opens[2] && closes[1] > opens[2] && opens[1] < closes[2]);
   bool bearEngulf = (closes[1] < opens[1] && closes[2] > opens[2] && closes[1] < opens[2] && opens[1] > closes[2]);
   bool bullEngulfZone = bullEngulf && (bullOBRetest || bullFVGEntry);
   bool bearEngulfZone = bearEngulf && (bearOBRetest || bearFVGEntry);

   double range1  = highs[1] - lows[1];
   double body1   = MathAbs(closes[1] - opens[1]);
   double upWick1 = highs[1] - MathMax(closes[1], opens[1]);
   double dnWick1 = MathMin(closes[1], opens[1]) - lows[1];
   double volSpike= (vol0 > volMA * 1.5);

   bool isHammer = (range1 > 0 && dnWick1 >= body1 * 2.0 && upWick1 < body1 * 0.5 && closes[1] > opens[1]);
   bool isSS     = (range1 > 0 && upWick1 >= body1 * 2.0 && dnWick1 < body1 * 0.5 && closes[1] < opens[1]);
   bool hammerZone = isHammer && volSpike && (bullOBRetest || bullFVGEntry);
   bool ssZone     = isSS     && volSpike && (bearOBRetest || bearFVGEntry);

   bool morningStar = (closes[3] < opens[3] && MathAbs(closes[2]-opens[2]) < (highs[2]-lows[2])*0.3 &&
                       closes[1] > opens[1] && closes[1] > (opens[3]+closes[3])/2.0);
   bool eveningStar = (closes[3] > opens[3] && MathAbs(closes[2]-opens[2]) < (highs[2]-lows[2])*0.3 &&
                       closes[1] < opens[1] && closes[1] < (opens[3]+closes[3])/2.0);

   bool isDoji    = (range1 > 0 && body1 < range1 * 0.15);
   bool dojiAtSup = isDoji && (bullOBRetest || bullFVGEntry || bprBullRetest);
   bool dojiAtRes = isDoji && (bearOBRetest || bearFVGEntry || bprBearRetest);

   // ── HTF Bias ──
   int htfBias1 = UseHTF1 ? GetHTFBias(HTF1) : 0;
   int htfBias2 = UseHTF2 ? GetHTFBias(HTF2) : 0;
   int htfBias3 = UseHTF3 ? GetHTFBias(HTF3) : 0;
   int htfBullCount = (htfBias1 == 1 ? 1 : 0) + (htfBias2 == 1 ? 1 : 0) + (htfBias3 == 1 ? 1 : 0);
   int htfBearCount = (htfBias1 == -1 ? 1 : 0) + (htfBias2 == -1 ? 1 : 0) + (htfBias3 == -1 ? 1 : 0);
   bool htfAlignBull = (htfBullCount >= 2);
   bool htfAlignBear = (htfBearCount >= 2);

   // ── God-Tier Hybrids ──
   bool wyckoffSpring   = (lows[1] < lastSwingLow && closes[0] > lastSwingLow && bullOBRetest && posVolDelta);
   bool wyckoffTerminal = (highs[1] > lastSwingHigh && closes[0] < lastSwingHigh && bearOBRetest && negVolDelta);
   bool threeDriveBull  = liqSweepBull && bullFVGEntry && bullOBRetest && oteBull;
   bool threeDriveBear  = liqSweepBear && bearFVGEntry && bearOBRetest && oteBear;

   // ── BULL SCORE ──
   double bScore = 0;
   if(UseOrderBlocks  && bullOBRetest)      bScore += 15;
   if(UseFVG          && bullFVGEntry)      bScore += 13;
   if(UseBreaker      && bullBreakerRetest) bScore += 11;
   if(UseUnicorn      && bullUnicorn)       bScore += 18;
   if(UseLiqSweep     && liqSweepBull)      bScore += 14;
   if(UseOTE          && oteBull)           bScore += 12;
   if(UseBPR          && bprBullRetest)     bScore += 9;
   if(UseInducement   && displacementUp)    bScore += 9;
   if(UseMSS          && mssUp)             bScore += 11;
   if(UseEngulfing    && bullEngulfZone)    bScore += 8;
   if(UseHammer       && hammerZone)        bScore += 8;
   if(UseMorningStar  && morningStar)       bScore += 7;
   if(UseDoji         && dojiAtSup)         bScore += 6;
   if(UseRegDiv       && multiRegBullDiv)   bScore += 9;
   if(UseHidDiv       && hidBullDiv)        bScore += 8;
   if(UseVolDelta     && posVolDelta && imbalanceBull) bScore += 12;
   if(UsePOCRej       && pocBull)           bScore += 7;
   if(UseBBSqueeze    && bbBreakupUp)       bScore += 7;
   if(UseSupertrend   && stOBBull)          bScore += 9;
   if(UseEMARibbon    && emaPullBull)       bScore += 7;
   if(UseIchimoku     && ichiBreakBull)     bScore += 7;
   if(UseKillZones    && kzBull)            bScore += 10;
   if(htfAlignBull)                         bScore += 13;
   if(liqSweepBull && bullFVGEntry && bullOBRetest && oteBull) bScore += 16;
   if(wyckoffSpring)                        bScore += 15;
   if(threeDriveBull)                       bScore += 14;

   // ── BEAR SCORE ──
   double beScore = 0;
   if(UseOrderBlocks  && bearOBRetest)      beScore += 15;
   if(UseFVG          && bearFVGEntry)      beScore += 13;
   if(UseBreaker      && bearBreakerRetest) beScore += 11;
   if(UseUnicorn      && bearUnicorn)       beScore += 18;
   if(UseLiqSweep     && liqSweepBear)      beScore += 14;
   if(UseOTE          && oteBear)           beScore += 12;
   if(UseBPR          && bprBearRetest)     beScore += 9;
   if(UseInducement   && displacementDown)  beScore += 9;
   if(UseMSS          && mssDown)           beScore += 11;
   if(UseEngulfing    && bearEngulfZone)    beScore += 8;
   if(UseHammer       && ssZone)            beScore += 8;
   if(UseMorningStar  && eveningStar)       beScore += 7;
   if(UseDoji         && dojiAtRes)         beScore += 6;
   if(UseRegDiv       && multiRegBearDiv)   beScore += 9;
   if(UseHidDiv       && hidBearDiv)        beScore += 8;
   if(UseVolDelta     && negVolDelta && imbalanceBear) beScore += 12;
   if(UsePOCRej       && pocBear)           beScore += 7;
   if(UseBBSqueeze    && bbBreakupDn)       beScore += 7;
   if(UseSupertrend   && stOBBear)          beScore += 9;
   if(UseEMARibbon    && emaPullBear)       beScore += 7;
   if(UseIchimoku     && ichiBreakBear)     beScore += 7;
   if(UseKillZones    && kzBear)            beScore += 10;
   if(htfAlignBear)                         beScore += 13;
   if(liqSweepBear && bearFVGEntry && bearOBRetest && oteBear) beScore += 16;
   if(wyckoffTerminal)                      beScore += 15;
   if(threeDriveBear)                       beScore += 14;

   double maxRaw = 260.0;
   bullScore = MathMin(100.0, MathRound(bScore  / maxRaw * 100.0));
   bearScore = MathMin(100.0, MathRound(beScore / maxRaw * 100.0));
}

//+------------------------------------------------------------------+
//| Trade Management                                                  |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol) count++;
   return count;
}

double CalcLotSize(double slPips)
{
   if(slPips <= 0) return 0.01;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotSize    = riskAmount / (slPips / tickSize * tickValue);
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   return MathMax(minLot, MathMin(maxLot, lotSize));
}

void OpenTrade(bool isBuy, double score)
{
   if(CountOpenTrades() >= MaxTrades) return;

   double atr  = GetATR(14);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;

   double sl, tp1, entry;
   if(isBuy)
   {
      entry = ask;
      sl    = entry - ATR_SL_Mult  * atr;
      tp1   = entry + ATR_TP1_Mult * atr;
   }
   else
   {
      entry = bid;
      sl    = entry + ATR_SL_Mult  * atr;
      tp1   = entry - ATR_TP1_Mult * atr;
   }

   double slPips = MathAbs(entry - sl);
   double lots   = CalcLotSize(slPips);
   if(lots <= 0) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lots;
   req.type      = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = isBuy ? ask : bid;
   req.sl        = NormalizeDouble(sl,  _Digits);
   req.tp        = NormalizeDouble(tp1, _Digits);
   req.deviation = 10;
   req.magic     = 202406;
   req.comment   = "GodMode " + DoubleToString(score, 0) + "/100";

   if(!OrderSend(req, res))
      Print("OrderSend failed: ", GetLastError(), " Score=", score);
   else
      Print("Trade opened: ", isBuy ? "BUY" : "SELL", " Lot=", lots, " Score=", score, "/100");
}

void ManageTrailingStop()
{
   if(!UseTrailingStop) return;
   double atr = GetATR(14);
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != 202406) continue;

      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      int    type   = (int)PositionGetInteger(POSITION_TYPE);
      double openP  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double newSL = curSL;
      if(type == POSITION_TYPE_BUY)
      {
         newSL = bid - TrailATRMult * atr;
         if(newSL <= curSL || newSL <= 0) continue;
      }
      else
      {
         newSL = ask + TrailATRMult * atr;
         if(newSL >= curSL || newSL <= 0) continue;
      }

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = _Symbol;
      req.position = ticket;
      req.sl       = NormalizeDouble(newSL, _Digits);
      req.tp       = curTP;
      OrderSend(req, res);
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar == lastBar) { ManageTrailingStop(); return; }
   lastBar = curBar;

   double bullScore = 0, bearScore = 0;
   CalculateScore(bullScore, bearScore);

   bool bullDom = (bullScore > bearScore + 5);
   bool bearDom = (bearScore > bullScore + 5);

   double finalBull = bullDom ? bullScore : 0;
   double finalBear = bearDom ? bearScore : 0;

   bool passSession = !FilterSessions || InKillZone();
   if(!passSession) return;

   bool godBuy    = ShowGodMode && (finalBull >= GodThreshold);
   bool godSell   = ShowGodMode && (finalBear >= GodThreshold);
   bool strongBuy = ShowStrong  && (finalBull >= StrongThreshold) && !godBuy;
   bool strongSell= ShowStrong  && (finalBear >= StrongThreshold) && !godSell;
   bool modBuy    = ShowModerate && (finalBull >= ModThreshold) && (finalBull < StrongThreshold);
   bool modSell   = ShowModerate && (finalBear >= ModThreshold) && (finalBear < StrongThreshold);

   if(godBuy || strongBuy)   OpenTrade(true,  finalBull);
   if(godSell || strongSell) OpenTrade(false, finalBear);

   if(godBuy || godSell || strongBuy || strongSell)
      Print("SIGNAL | Bull:", finalBull, " Bear:", finalBear,
            godBuy?"  ★GOD BUY★":strongBuy?"  STRONG BUY":"",
            godSell?"  ★GOD SELL★":strongSell?"  STRONG SELL":"");
}
//+------------------------------------------------------------------+

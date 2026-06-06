//+------------------------------------------------------------------+
//|  ULTIMATE v7 GOD MODE EA — ICT/SMC Confluence                   |
//|  Converted from Pine Script by Onwun                            |
//|  MQL5 Expert Advisor — Full Auto Trading                        |
//|  v7 FIXES: Lower thresholds, Moderate signal trading,           |
//|            Relaxed volume/liquidity conditions,                  |
//|            Warm-up bar seeding for OB/FVG/Structure             |
//+------------------------------------------------------------------+
#property copyright "ULTIMATE GOD MODE EA v7"
#property version   "7.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>

CTrade    trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUT GROUPS                                                     |
//+------------------------------------------------------------------+

// Core
input group "⚙️ Core Settings"
input bool   i_showStrong     = true;   // Show Strong Signals
input bool   i_showMod        = true;   // Show Moderate Signals
input bool   i_showGod        = true;   // Show God Mode Signals
input bool   i_autoTrade      = true;   // Enable Auto Trading
input double i_lotSize        = 0.01;   // Lot Size
input double i_riskPercent    = 1.0;    // Risk % per trade
input int    i_maxTrades      = 3;      // Max open trades

// Score Thresholds — LOWERED from v6
input group "📊 Score & God Mode"
input int    i_strongThr      = 60;     // Strong Signal Threshold (was 85)
input int    i_modThr         = 40;     // Moderate Signal Threshold (was 70)
input int    i_godThr         = 80;     // God Mode Threshold (was 95)
input bool   i_tradeOnMod     = true;   // Trade on Moderate Signals (NEW)

// MTF
input group "🕐 Multi-Timeframe"
input ENUM_TIMEFRAMES i_tf1   = PERIOD_H1;
input ENUM_TIMEFRAMES i_tf2   = PERIOD_H4;
input ENUM_TIMEFRAMES i_tf3   = PERIOD_D1;
input ENUM_TIMEFRAMES i_tf4   = PERIOD_W1;
input ENUM_TIMEFRAMES i_tf5   = PERIOD_MN1;
input bool   i_useTF1         = true;
input bool   i_useTF2         = true;
input bool   i_useTF3         = true;
input bool   i_useTF4         = false;
input bool   i_useTF5         = false;

// ICT/SMC
input group "🏦 ICT / SMC Modules"
input bool   i_useOB          = true;
input bool   i_useFVG         = true;
input bool   i_useBreaker     = true;
input bool   i_useUnicorn     = true;
input bool   i_useLiqSweep    = true;
input bool   i_useOTE         = true;
input bool   i_useBPR         = true;
input bool   i_useInducement  = true;
input bool   i_useMSS         = true;
input bool   i_useKZ          = true;
input bool   i_useHTFOB       = true;

// Classical TA
input group "📈 Classical TA Modules"
input bool   i_useEngulf      = true;
input bool   i_useHammer      = true;
input bool   i_useStar        = true;
input bool   i_useDoji        = true;
input bool   i_useDivReg      = true;
input bool   i_useDivHid      = true;
input bool   i_useBBSqz       = true;
input bool   i_useST          = true;
input bool   i_useEMA         = true;
input bool   i_useIchi        = true;

// Volume
input group "📦 Volume / Footprint"
input bool   i_useVolDelta    = true;
input bool   i_useFootPOC     = true;

// Trade Management — SL increased from v6
input group "💰 Trade Management"
input double i_slATRMult      = 2.5;    // SL ATR Multiplier (was 1.5)
input double i_tp1ATRMult     = 2.0;
input double i_tp2ATRMult     = 3.0;
input double i_tp3ATRMult     = 4.0;
input bool   i_useTrailStop   = true;
input double i_trailATRMult   = 1.0;
input bool   i_useBreakEven   = true;
input double i_beATRMult      = 1.5;

// Sessions
input group "🕐 Session Filters"
input bool   i_sessFilter     = false;
input int    i_asianStart     = 0;
input int    i_asianEnd       = 2;
input int    i_londonStart    = 7;
input int    i_londonEnd      = 10;
input int    i_nyStart        = 13;
input int    i_nyEnd          = 17;

// Pivot
input int    i_pivLen         = 3;      // Pivot Lookback (was 5 — reduced for faster detection)

// Warm-up
input int    i_warmupBars     = 100;    // Bars to seed OB/FVG/Structure on init (NEW)

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
#define MAX_OB  8
#define MAX_FVG 12

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

OBZone  bullOBs[MAX_OB];
OBZone  bearOBs[MAX_OB];
FVGZone fvgZones[MAX_FVG];
int     bullOBCount = 0;
int     bearOBCount = 0;
int     fvgCount    = 0;

int     structTrend      = 0;
double  prevSwingHigh    = 0;
double  prevSwingLow     = 0;
double  lastSwingHigh    = 0;
double  lastSwingLow     = 0;
int     lastSwingHighBar = 0;
int     lastSwingLowBar  = 0;

double  lastRsiHigh  = 0;
double  lastRsiLow   = 0;
double  lastPriceHigh = 0;
double  lastPriceLow  = 0;

int     atrHandle, rsiHandle, macdHandle, stochHandle;
int     ema8Handle, ema13Handle, ema21Handle, ema34Handle, ema55Handle;
int     bbHandle;

datetime lastBarTime = 0;
int      magicNumber = 20260701;   // Changed from v6 to avoid conflict

//+------------------------------------------------------------------+
//| Helper: Get HTF bias                                             |
//+------------------------------------------------------------------+
int GetHTFBias(ENUM_TIMEFRAMES tf) {
   double c = iClose(Symbol(), tf, 1);
   double o = iOpen(Symbol(),  tf, 1);
   if(c == 0 || o == 0) return 0;
   return c > o ? 1 : c < o ? -1 : 0;
}

//+------------------------------------------------------------------+
//| Helper: Pivot High/Low detection                                 |
//+------------------------------------------------------------------+
double PivotHigh(int len, int shift = 0) {
   double pivot = iHigh(Symbol(), PERIOD_CURRENT, len + shift);
   if(pivot == 0) return 0;
   for(int i = shift; i < 2 * len + 1 + shift; i++) {
      if(i == len + shift) continue;
      if(iHigh(Symbol(), PERIOD_CURRENT, i) >= pivot) return 0;
   }
   return pivot;
}

double PivotLow(int len, int shift = 0) {
   double pivot = iLow(Symbol(), PERIOD_CURRENT, len + shift);
   if(pivot == 0) return 0;
   for(int i = shift; i < 2 * len + 1 + shift; i++) {
      if(i == len + shift) continue;
      if(iLow(Symbol(), PERIOD_CURRENT, i) <= pivot) return 0;
   }
   return pivot;
}

//+------------------------------------------------------------------+
//| Helper: ATR value                                                |
//+------------------------------------------------------------------+
double GetATR(int period = 14, int shift = 1) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, shift, 1, buf) <= 0) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: RSI value                                                |
//+------------------------------------------------------------------+
double GetRSI(int shift = 1) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(rsiHandle, 0, shift, 1, buf) <= 0) return 50;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: EMA value                                                |
//+------------------------------------------------------------------+
double GetEMA(int handle, int shift = 1) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: BB values                                                |
//+------------------------------------------------------------------+
void GetBB(double &upper, double &lower, double &basis, int shift = 1) {
   double u[], l[], b[];
   ArraySetAsSeries(u, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(b, true);
   CopyBuffer(bbHandle, 1, shift, 1, u);
   CopyBuffer(bbHandle, 2, shift, 1, l);
   CopyBuffer(bbHandle, 0, shift, 1, b);
   upper = u[0]; lower = l[0]; basis = b[0];
}

//+------------------------------------------------------------------+
//| Helper: VWAP proxy (EMA21)                                       |
//+------------------------------------------------------------------+
double GetVWAP(int shift = 1) {
   return GetEMA(ema21Handle, shift);
}

//+------------------------------------------------------------------+
//| Helper: Stochastic                                               |
//+------------------------------------------------------------------+
double GetStochK(int shift = 1) {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(stochHandle, 0, shift, 1, buf) <= 0) return 50;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Helper: Volume delta proxy                                       |
//+------------------------------------------------------------------+
double GetVolumeDelta(int shift = 1) {
   double vol   = (double)iVolume(Symbol(), PERIOD_CURRENT, shift);
   double c     = iClose(Symbol(), PERIOD_CURRENT, shift);
   double o     = iOpen(Symbol(),  PERIOD_CURRENT, shift);
   double h     = iHigh(Symbol(),  PERIOD_CURRENT, shift);
   double l     = iLow(Symbol(),   PERIOD_CURRENT, shift);
   double range = h - l;
   if(range == 0) return 0;
   double buyVol  = c > o ? vol : vol * ((c - l) / range);
   double sellVol = vol - buyVol;
   return buyVol - sellVol;
}

//+------------------------------------------------------------------+
//| Helper: Average volume                                           |
//+------------------------------------------------------------------+
double AvgVolume(int period = 20, int shift = 1) {
   double total = 0;
   for(int i = shift; i < shift + period; i++)
      total += (double)iVolume(Symbol(), PERIOD_CURRENT, i);
   return total / period;
}

//+------------------------------------------------------------------+
//| Helper: Kill zone check                                          |
//+------------------------------------------------------------------+
bool InKillZone() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool asian  = (h >= i_asianStart  && h < i_asianEnd);
   bool london = (h >= i_londonStart && h < i_londonEnd);
   bool ny     = (h >= i_nyStart     && h < i_nyEnd);
   return asian || london || ny;
}

//+------------------------------------------------------------------+
//| Helper: Count open trades                                        |
//+------------------------------------------------------------------+
int CountTrades() {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(posInfo.SelectByIndex(i)) {
         if(posInfo.Symbol() == Symbol() && posInfo.Magic() == magicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Helper: Lot size from risk %                                     |
//+------------------------------------------------------------------+
double CalcLotSize(double slPips) {
   if(slPips <= 0) return i_lotSize;
   double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk     = balance * i_riskPercent / 100.0;
   double lots     = risk / (slPips / tickSize * tickVal);
   double minLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / stepLot) * stepLot;
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
//| Supertrend calculation                                           |
//+------------------------------------------------------------------+
double GetSupertrend(int &dir, int shift = 1) {
   double atr   = GetATR(10, shift);
   double hl2   = (iHigh(Symbol(), PERIOD_CURRENT, shift) + iLow(Symbol(), PERIOD_CURRENT, shift)) / 2.0;
   double upper = hl2 - 3.0 * atr;
   double lower = hl2 + 3.0 * atr;
   double c     = iClose(Symbol(), PERIOD_CURRENT, shift);
   double cprev = iClose(Symbol(), PERIOD_CURRENT, shift + 1);
   static double stFinal = 0;
   static int    stDir   = 0;
   if(stFinal == 0) { stFinal = upper; stDir = 1; }
   double newFinal;
   if(cprev > stFinal)
      newFinal = MathMax(upper, stFinal);
   else
      newFinal = MathMin(lower, stFinal);
   stDir   = c > newFinal ? 1 : -1;
   stFinal = newFinal;
   dir = stDir;
   return stFinal;
}

//+------------------------------------------------------------------+
//| Update OB zones                                                  |
//+------------------------------------------------------------------+
void UpdateOrderBlocks(bool bosUp, bool bosDown, bool chochUp, bool chochDown) {
   if((bosUp || chochUp) && lastSwingLowBar > 0) {
      for(int idx = 1; idx < 15 && idx <= Bars(Symbol(), PERIOD_CURRENT) - lastSwingLowBar; idx++) {
         double c = iClose(Symbol(), PERIOD_CURRENT, idx);
         double o = iOpen(Symbol(),  PERIOD_CURRENT, idx);
         if(c < o) {
            OBZone ob;
            ob.top = MathMax(o, c);
            ob.bot = MathMin(o, c);
            ob.startBar = iBarShift(Symbol(), PERIOD_CURRENT, iTime(Symbol(), PERIOD_CURRENT, idx));
            ob.mitigated = false;
            if(bullOBCount < MAX_OB) {
               for(int j = bullOBCount; j > 0; j--) bullOBs[j] = bullOBs[j-1];
               bullOBs[0] = ob; bullOBCount++;
            } else {
               for(int j = MAX_OB-1; j > 0; j--) bullOBs[j] = bullOBs[j-1];
               bullOBs[0] = ob;
            }
            break;
         }
      }
   }
   if((bosDown || chochDown) && lastSwingHighBar > 0) {
      for(int idx = 1; idx < 15 && idx <= Bars(Symbol(), PERIOD_CURRENT) - lastSwingHighBar; idx++) {
         double c = iClose(Symbol(), PERIOD_CURRENT, idx);
         double o = iOpen(Symbol(),  PERIOD_CURRENT, idx);
         if(c > o) {
            OBZone ob;
            ob.top = MathMax(o, c);
            ob.bot = MathMin(o, c);
            ob.startBar = iBarShift(Symbol(), PERIOD_CURRENT, iTime(Symbol(), PERIOD_CURRENT, idx));
            ob.mitigated = false;
            if(bearOBCount < MAX_OB) {
               for(int j = bearOBCount; j > 0; j--) bearOBs[j] = bearOBs[j-1];
               bearOBs[0] = ob; bearOBCount++;
            } else {
               for(int j = MAX_OB-1; j > 0; j--) bearOBs[j] = bearOBs[j-1];
               bearOBs[0] = ob;
            }
            break;
         }
      }
   }
   double c1 = iClose(Symbol(), PERIOD_CURRENT, 1);
   for(int i = 0; i < bullOBCount; i++)
      if(!bullOBs[i].mitigated && c1 < bullOBs[i].bot) bullOBs[i].mitigated = true;
   for(int i = 0; i < bearOBCount; i++)
      if(!bearOBs[i].mitigated && c1 > bearOBs[i].top) bearOBs[i].mitigated = true;
}

//+------------------------------------------------------------------+
//| Update FVG zones                                                 |
//+------------------------------------------------------------------+
void UpdateFVGs() {
   double l1 = iLow(Symbol(),  PERIOD_CURRENT, 1);
   double h3 = iHigh(Symbol(), PERIOD_CURRENT, 3);
   double h1 = iHigh(Symbol(), PERIOD_CURRENT, 1);
   double l3 = iLow(Symbol(),  PERIOD_CURRENT, 3);

   if(l1 > h3) {
      FVGZone fvg;
      fvg.top = l1; fvg.bot = h3;
      fvg.startBar = 1; fvg.bullish = true; fvg.filled = false;
      if(fvg.top > fvg.bot) {
         if(fvgCount < MAX_FVG) {
            for(int j = fvgCount; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg; fvgCount++;
         } else {
            for(int j = MAX_FVG-1; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg;
         }
      }
   }
   if(h1 < l3) {
      FVGZone fvg;
      fvg.top = l3; fvg.bot = h1;
      fvg.startBar = 1; fvg.bullish = false; fvg.filled = false;
      if(fvg.top > fvg.bot) {
         if(fvgCount < MAX_FVG) {
            for(int j = fvgCount; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg; fvgCount++;
         } else {
            for(int j = MAX_FVG-1; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg;
         }
      }
   }
   double c1  = iClose(Symbol(), PERIOD_CURRENT, 1);
   double hh1 = iHigh(Symbol(),  PERIOD_CURRENT, 1);
   double ll1 = iLow(Symbol(),   PERIOD_CURRENT, 1);
   for(int i = 0; i < fvgCount; i++) {
      if(!fvgZones[i].filled) {
         if(fvgZones[i].bullish  && ll1 <= fvgZones[i].top) fvgZones[i].filled = true;
         if(!fvgZones[i].bullish && hh1 >= fvgZones[i].bot) fvgZones[i].filled = true;
      }
   }
}

//+------------------------------------------------------------------+
//| WARM-UP: Seed structure/OB/FVG from historical bars              |
//| FIX: Prevents zero-trade issue caused by empty arrays on start   |
//+------------------------------------------------------------------+
void WarmUpHistory() {
   int bars = MathMin(i_warmupBars, Bars(Symbol(), PERIOD_CURRENT) - 10);
   Print("v7: Warming up ", bars, " historical bars...");

   for(int b = bars; b >= i_pivLen + 2; b--) {
      // Detect pivots historically
      double pH = PivotHigh(i_pivLen, b);
      double pL = PivotLow(i_pivLen,  b);

      if(pH > 0) {
         if(prevSwingHigh > 0) {
            bool bUp   = (structTrend == 1)  && pH > prevSwingHigh;
            bool cUp   = (structTrend != 1)  && pH > prevSwingHigh;
            if(bUp || cUp) {
               if(cUp) structTrend = 1;
               UpdateOrderBlocks(bUp, false, cUp, false);
            }
         }
         prevSwingHigh = pH;
         lastSwingHigh = pH;
         lastSwingHighBar = b;
      }
      if(pL > 0) {
         if(prevSwingLow > 0) {
            bool bDn  = (structTrend == -1) && pL < prevSwingLow;
            bool cDn  = (structTrend != -1) && pL < prevSwingLow;
            if(bDn || cDn) {
               if(cDn) structTrend = -1;
               UpdateOrderBlocks(false, bDn, false, cDn);
            }
         }
         prevSwingLow = pL;
         lastSwingLow = pL;
         lastSwingLowBar = b;
      }
      // Detect FVGs historically (approximate — uses shifted bars)
      double l1h = iLow(Symbol(),  PERIOD_CURRENT, b);
      double h3h = iHigh(Symbol(), PERIOD_CURRENT, b + 2);
      double h1h = iHigh(Symbol(), PERIOD_CURRENT, b);
      double l3h = iLow(Symbol(),  PERIOD_CURRENT, b + 2);
      if(l1h > h3h && l1h > h3h) {
         FVGZone fvg;
         fvg.top = l1h; fvg.bot = h3h;
         fvg.startBar = b; fvg.bullish = true; fvg.filled = false;
         if(fvg.top > fvg.bot && fvgCount < MAX_FVG) {
            for(int j = fvgCount; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg; fvgCount++;
         }
      }
      if(h1h < l3h) {
         FVGZone fvg;
         fvg.top = l3h; fvg.bot = h1h;
         fvg.startBar = b; fvg.bullish = false; fvg.filled = false;
         if(fvg.top > fvg.bot && fvgCount < MAX_FVG) {
            for(int j = fvgCount; j > 0; j--) fvgZones[j] = fvgZones[j-1];
            fvgZones[0] = fvg; fvgCount++;
         }
      }
   }
   Print("v7 Warm-up complete. BullOBs:", bullOBCount, " BearOBs:", bearOBCount, " FVGs:", fvgCount, " Trend:", structTrend);
}

//+------------------------------------------------------------------+
//| MAIN SCORING FUNCTION                                            |
//+------------------------------------------------------------------+
void CalcScores(double &bullScore, double &bearScore) {
   double bScore  = 0;
   double beScore = 0;

   double c0 = iClose(Symbol(), PERIOD_CURRENT, 0);
   double c1 = iClose(Symbol(), PERIOD_CURRENT, 1);
   double c2 = iClose(Symbol(), PERIOD_CURRENT, 2);
   double c3 = iClose(Symbol(), PERIOD_CURRENT, 3);
   double o1 = iOpen(Symbol(),  PERIOD_CURRENT, 1);
   double o2 = iOpen(Symbol(),  PERIOD_CURRENT, 2);
   double o3 = iOpen(Symbol(),  PERIOD_CURRENT, 3);
   double h1 = iHigh(Symbol(),  PERIOD_CURRENT, 1);
   double h2 = iHigh(Symbol(),  PERIOD_CURRENT, 2);
   double l1 = iLow(Symbol(),   PERIOD_CURRENT, 1);
   double l2 = iLow(Symbol(),   PERIOD_CURRENT, 2);

   // === PIVOT STRUCTURE ===
   double pivHigh = PivotHigh(i_pivLen, i_pivLen);
   double pivLow  = PivotLow(i_pivLen,  i_pivLen);

   if(pivHigh > 0) { lastSwingHigh = pivHigh; lastSwingHighBar = i_pivLen; }
   if(pivLow  > 0) { lastSwingLow  = pivLow;  lastSwingLowBar  = i_pivLen; }

   // === BOS / CHoCH ===
   bool bosUp = false, bosDown = false, chochUp = false, chochDown = false;
   if(pivHigh > 0 && prevSwingHigh > 0) {
      if(pivHigh > prevSwingHigh) {
         chochUp = (structTrend != 1);
         bosUp   = (structTrend == 1);
         structTrend = 1;
      }
   }
   if(pivLow > 0 && prevSwingLow > 0) {
      if(pivLow < prevSwingLow) {
         chochDown = (structTrend != -1);
         bosDown   = (structTrend == -1);
         structTrend = -1;
      }
   }
   if(pivHigh > 0) prevSwingHigh = pivHigh;
   if(pivLow  > 0) prevSwingLow  = pivLow;

   bool mssUp   = chochUp;
   bool mssDown = chochDown;

   UpdateOrderBlocks(bosUp, bosDown, chochUp, chochDown);
   UpdateFVGs();

   // === OB RETEST ===
   bool bullOBRetest = false, bearOBRetest = false;
   for(int i = 0; i < bullOBCount; i++) {
      if(!bullOBs[i].mitigated && l1 <= bullOBs[i].top && l1 >= bullOBs[i].bot && c1 > bullOBs[i].bot)
         bullOBRetest = true;
   }
   for(int i = 0; i < bearOBCount; i++) {
      if(!bearOBs[i].mitigated && h1 >= bearOBs[i].bot && h1 <= bearOBs[i].top && c1 < bearOBs[i].top)
         bearOBRetest = true;
   }

   // === FVG ENTRY ===
   bool bullFVGEntry = false, bearFVGEntry = false;
   for(int i = 0; i < fvgCount; i++) {
      if(!fvgZones[i].filled) {
         if(fvgZones[i].bullish  && l1 <= fvgZones[i].top && l1 >= fvgZones[i].bot && c1 > fvgZones[i].bot)
            bullFVGEntry = true;
         if(!fvgZones[i].bullish && h1 >= fvgZones[i].bot && h1 <= fvgZones[i].top && c1 < fvgZones[i].top)
            bearFVGEntry = true;
      }
   }

   // === BREAKER BLOCKS ===
   bool bullBreakerRetest = false, bearBreakerRetest = false;
   for(int i = 0; i < bullOBCount; i++) {
      if(bullOBs[i].mitigated && h1 >= bullOBs[i].bot && h1 <= bullOBs[i].top && c1 < bullOBs[i].bot)
         bearBreakerRetest = true;
   }
   for(int i = 0; i < bearOBCount; i++) {
      if(bearOBs[i].mitigated && l1 <= bearOBs[i].top && l1 >= bearOBs[i].bot && c1 > bearOBs[i].top)
         bullBreakerRetest = true;
   }

   // === UNICORN ===
   bool bullUnicorn = bullFVGEntry && bullBreakerRetest;
   bool bearUnicorn = bearFVGEntry && bearBreakerRetest;

   // === LIQUIDITY SWEEP + BOS (RELAXED: BOS no longer required on same bar) ===
   // FIX v7: Removed the && bosUp/bosDown requirement — too rare on same candle
   bool liqSweepBull = lastSwingLow > 0 && l1 < lastSwingLow && c1 > lastSwingLow;
   bool liqSweepBear = lastSwingHigh > 0 && h1 > lastSwingHigh && c1 < lastSwingHigh;

   // === OTE FIBO ===
   bool oteBull = false, oteBear = false;
   if(lastSwingHigh > 0 && lastSwingLow > 0 && lastSwingHigh > lastSwingLow) {
      double rng = lastSwingHigh - lastSwingLow;
      double oteZoneBullTop = lastSwingHigh - 0.618 * rng;
      double oteZoneBullBot = lastSwingHigh - 0.786 * rng;
      double oteZoneBearTop = lastSwingLow  + 0.786 * rng;
      double oteZoneBearBot = lastSwingLow  + 0.618 * rng;
      oteBull = l1 <= oteZoneBullTop && l1 >= oteZoneBullBot && structTrend == 1;
      oteBear = h1 >= oteZoneBearBot && h1 <= oteZoneBearTop && structTrend == -1;
   }

   // === BPR ===
   bool bprBullRetest = false, bprBearRetest = false;
   if(fvgCount >= 2) {
      double overlapTop = MathMin(fvgZones[0].top, fvgZones[1].top);
      double overlapBot = MathMax(fvgZones[0].bot, fvgZones[1].bot);
      if(overlapTop > overlapBot && fvgZones[0].bullish != fvgZones[1].bullish) {
         bprBullRetest = l1 <= overlapTop && l1 >= overlapBot && structTrend == 1;
         bprBearRetest = h1 >= overlapBot && h1 <= overlapTop && structTrend == -1;
      }
   }

   // === DISPLACEMENT / INDUCEMENT ===
   double ticksz = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double eqHigh = MathAbs(h2 - iHigh(Symbol(), PERIOD_CURRENT, 4)) < ticksz * 5 ? h2 : 0;
   double eqLow  = MathAbs(l2 - iLow(Symbol(),  PERIOD_CURRENT, 4)) < ticksz * 5 ? l2 : 0;
   double range1 = h1 - l1;
   bool displacementUp   = eqLow  > 0 && l1 < eqLow  && c1 > eqLow  && range1 > 0 && (c1 - o1) > range1 * 0.6;
   bool displacementDown = eqHigh > 0 && h1 > eqHigh && c1 < eqHigh && range1 > 0 && (o1 - c1) > range1 * 0.6;

   // === KILL ZONES ===
   bool inKillZone = InKillZone();
   bool kzLiqBull  = inKillZone && liqSweepBull;
   bool kzLiqBear  = inKillZone && liqSweepBear;

   // === VOLUME DELTA (RELAXED thresholds from v6) ===
   double delta    = GetVolumeDelta(1);
   double deltaAvg = 0;
   for(int i = 1; i <= 14; i++) deltaAvg += GetVolumeDelta(i);
   deltaAvg /= 14.0;
   double vol1   = (double)iVolume(Symbol(), PERIOD_CURRENT, 1);
   double avgVol = AvgVolume(20, 1);
   // FIX v7: Reduced from 1.5/1.8 to 1.1/1.3 — much easier to satisfy
   bool imbalanceBull = delta > deltaAvg * 1.1 && vol1 > avgVol * 1.3;
   bool imbalanceBear = delta < deltaAvg * -1.1 && vol1 > avgVol * 1.3;
   bool posVolDeltaAtZone = (delta > deltaAvg && delta > 0) && (bullFVGEntry || bullOBRetest);
   bool negVolDeltaAtZone = (delta < deltaAvg && delta < 0) && (bearFVGEntry || bearOBRetest);

   // === POC REJECTION ===
   double vwap1 = GetVWAP(1);
   bool pocRejBull = l1 <= vwap1 && c1 > vwap1 && structTrend == 1;
   bool pocRejBear = h1 >= vwap1 && c1 < vwap1 && structTrend == -1;

   // === RSI DIVERGENCE ===
   double rsiPivL = PivotLow(i_pivLen, i_pivLen) > 0 ? GetRSI(i_pivLen + i_pivLen) : 0;
   double rsiPivH = PivotHigh(i_pivLen, i_pivLen) > 0 ? GetRSI(i_pivLen + i_pivLen) : 0;
   bool regBullDiv = pivLow  > 0 && lastPriceLow  > 0 && pivLow  < lastPriceLow  && rsiPivL > lastRsiLow;
   bool regBearDiv = pivHigh > 0 && lastPriceHigh > 0 && pivHigh > lastPriceHigh && rsiPivH < lastRsiHigh;
   bool hidBullDiv = pivLow  > 0 && lastPriceLow  > 0 && pivLow  > lastPriceLow  && rsiPivL < lastRsiLow;
   bool hidBearDiv = pivHigh > 0 && lastPriceHigh > 0 && pivHigh < lastPriceHigh && rsiPivH > lastRsiHigh;
   bool multiRegBullDiv = regBullDiv;
   bool multiRegBearDiv = regBearDiv;
   if(pivLow  > 0) { lastPriceLow  = pivLow;  lastRsiLow  = GetRSI(i_pivLen); }
   if(pivHigh > 0) { lastPriceHigh = pivHigh; lastRsiHigh = GetRSI(i_pivLen); }

   // === EMA RIBBON ===
   double e8  = GetEMA(ema8Handle,  1);
   double e13 = GetEMA(ema13Handle, 1);
   double e21 = GetEMA(ema21Handle, 1);
   double e34 = GetEMA(ema34Handle, 1);
   double e55 = GetEMA(ema55Handle, 1);
   bool emaRibbonBull  = e8 > e13 && e13 > e21 && e21 > e34 && e34 > e55;
   bool emaRibbonBear  = e8 < e13 && e13 < e21 && e21 < e34 && e34 < e55;
   bool emaPullbackBull = emaRibbonBull && l1 <= e21 && c1 > e21 && structTrend == 1;
   bool emaPullbackBear = emaRibbonBear && h1 >= e21 && c1 < e21 && structTrend == -1;

   // === BOLLINGER BANDS ===
   double bbUpper, bbLower, bbBasis;
   GetBB(bbUpper, bbLower, bbBasis, 1);
   double bbWidth = bbUpper - bbLower;
   double bbWidthAvg = 0;
   for(int i = 1; i <= 20; i++) {
      double u, l, b;
      GetBB(u, l, b, i);
      bbWidthAvg += u - l;
   }
   bbWidthAvg /= 20.0;
   double u2, l2b, b2;
   GetBB(u2, l2b, b2, 2);
   bool bbSqueeze2  = (u2 - l2b) < bbWidthAvg * 0.7;
   bool bbBreakoutUp = bbSqueeze2 && c1 > bbUpper && emaRibbonBull;
   bool bbBreakoutDn = bbSqueeze2 && c1 < bbLower && emaRibbonBear;

   // === SUPERTREND ===
   int stDir1, stDir2;
   GetSupertrend(stDir1, 1);
   GetSupertrend(stDir2, 2);
   bool stFlipUp    = stDir1 == 1  && stDir2 == -1;
   bool stFlipDown  = stDir1 == -1 && stDir2 == 1;
   bool stFlipOBBull = stFlipUp   && bullOBRetest;
   bool stFlipOBBear = stFlipDown && bearOBRetest;

   // === ICHIMOKU ===
   double ichiConv, ichiBase;
   double convH = 0, convL = 99999999, baseH = 0, baseL = 99999999;
   for(int i = 1; i <= 9;  i++) { convH = MathMax(convH, iHigh(Symbol(), PERIOD_CURRENT, i)); convL = MathMin(convL, iLow(Symbol(), PERIOD_CURRENT, i)); }
   for(int i = 1; i <= 26; i++) { baseH = MathMax(baseH, iHigh(Symbol(), PERIOD_CURRENT, i)); baseL = MathMin(baseL, iLow(Symbol(), PERIOD_CURRENT, i)); }
   ichiConv = (convH + convL) / 2.0;
   ichiBase = (baseH + baseL) / 2.0;
   double lb52H = 0, lb52L = 99999999;
   for(int i = 1; i <= 52; i++) { lb52H = MathMax(lb52H, iHigh(Symbol(), PERIOD_CURRENT, i)); lb52L = MathMin(lb52L, iLow(Symbol(), PERIOD_CURRENT, i)); }
   double ichiLeadA = (ichiConv + ichiBase) / 2.0;
   double ichiLeadB = (lb52H + lb52L) / 2.0;
   double cH2 = 0, cL2 = 99999999, bH2 = 0, bL2 = 99999999;
   for(int i = 2; i <= 10; i++) { cH2 = MathMax(cH2, iHigh(Symbol(), PERIOD_CURRENT, i)); cL2 = MathMin(cL2, iLow(Symbol(), PERIOD_CURRENT, i)); }
   for(int i = 2; i <= 27; i++) { bH2 = MathMax(bH2, iHigh(Symbol(), PERIOD_CURRENT, i)); bL2 = MathMin(bL2, iLow(Symbol(), PERIOD_CURRENT, i)); }
   double ichiConvPrev = (cH2 + cL2) / 2.0;
   double ichiBasePrev = (bH2 + bL2) / 2.0;
   bool tkCrossUp    = ichiConv > ichiBase && ichiConvPrev <= ichiBasePrev;
   bool tkCrossDown  = ichiConv < ichiBase && ichiConvPrev >= ichiBasePrev;
   bool cloudBull    = ichiLeadA > ichiLeadB;
   bool cloudBear    = ichiLeadA < ichiLeadB;
   bool ichiBreakBull = tkCrossUp   && cloudBull && c1 > MathMax(ichiLeadA, ichiLeadB);
   bool ichiBreakBear = tkCrossDown && cloudBear && c1 < MathMin(ichiLeadA, ichiLeadB);

   // === CANDLE PATTERNS ===
   bool bullEngulf = c1 > o1 && c2 < o2 && c1 > o2 && o1 < c2;
   bool bearEngulf = c1 < o1 && c2 > o2 && c1 < o2 && o1 > c2;
   bool bullEngulfAtZone = bullEngulf && (bullOBRetest || bullFVGEntry);
   bool bearEngulfAtZone = bearEngulf && (bearOBRetest || bearFVGEntry);

   double candleRange1 = h1 - l1;
   double bodySize1    = MathAbs(c1 - o1);
   double upperWick1   = h1 - MathMax(c1, o1);
   double lowerWick1   = MathMin(c1, o1) - l1;
   bool isHammer       = candleRange1 > 0 && lowerWick1 >= bodySize1 * 2.0 && upperWick1 < bodySize1 * 0.5 && c1 > o1;
   bool isShootingStar = candleRange1 > 0 && upperWick1 >= bodySize1 * 2.0 && lowerWick1 < bodySize1 * 0.5 && c1 < o1;
   bool volSpike       = vol1 > avgVol * 1.3;   // FIX v7: was 1.5
   bool hammerAtZone   = isHammer       && volSpike && (bullOBRetest || bullFVGEntry);
   bool ssAtZone       = isShootingStar && volSpike && (bearOBRetest || bearFVGEntry);

   double c4 = iClose(Symbol(), PERIOD_CURRENT, 4);
   double o4 = iOpen(Symbol(),  PERIOD_CURRENT, 4);
   bool morningStar = c4 < o4 && MathAbs(c3 - o3) < (iHigh(Symbol(), PERIOD_CURRENT, 3) - iLow(Symbol(), PERIOD_CURRENT, 3)) * 0.3 && c2 > o2 && c2 > (o4 + c4) / 2.0;
   bool eveningStar = c4 > o4 && MathAbs(c3 - o3) < (iHigh(Symbol(), PERIOD_CURRENT, 3) - iLow(Symbol(), PERIOD_CURRENT, 3)) * 0.3 && c2 < o2 && c2 < (o4 + c4) / 2.0;

   bool isDoji    = candleRange1 > 0 && bodySize1 < candleRange1 * 0.15;
   bool dojiAtSup = isDoji && (bullOBRetest || bullFVGEntry || bprBullRetest);
   bool dojiAtRes = isDoji && (bearOBRetest || bearFVGEntry || bprBearRetest);

   // === HTF BIAS ===
   int htfBullCount = 0, htfBearCount = 0;
   if(i_useTF1) { int b = GetHTFBias(i_tf1); if(b > 0) htfBullCount++; else if(b < 0) htfBearCount++; }
   if(i_useTF2) { int b = GetHTFBias(i_tf2); if(b > 0) htfBullCount++; else if(b < 0) htfBearCount++; }
   if(i_useTF3) { int b = GetHTFBias(i_tf3); if(b > 0) htfBullCount++; else if(b < 0) htfBearCount++; }
   if(i_useTF4) { int b = GetHTFBias(i_tf4); if(b > 0) htfBullCount++; else if(b < 0) htfBearCount++; }
   if(i_useTF5) { int b = GetHTFBias(i_tf5); if(b > 0) htfBullCount++; else if(b < 0) htfBearCount++; }
   bool htfAlignBull = htfBullCount > htfBearCount;
   bool htfAlignBear = htfBearCount > htfBullCount;
   bool htfLTFBull   = htfAlignBull && structTrend == 1;
   bool htfLTFBear   = htfAlignBear && structTrend == -1;

   // === WEEKLY/MONTHLY OB ===
   double wClose = iClose(Symbol(), PERIOD_W1,  1);
   double wOpen  = iOpen(Symbol(),  PERIOD_W1,  1);
   double mClose = iClose(Symbol(), PERIOD_MN1, 1);
   double mOpen  = iOpen(Symbol(),  PERIOD_MN1, 1);
   bool weeklyOBBull  = wClose > wOpen && l1 <= MathMax(wClose, wOpen) && l1 >= MathMin(wClose, wOpen);
   bool weeklyOBBear  = wClose < wOpen && h1 >= MathMin(wClose, wOpen) && h1 <= MathMax(wClose, wOpen);
   bool monthlyOBBull = mClose > mOpen && l1 <= MathMax(mClose, mOpen) && l1 >= MathMin(mClose, mOpen);
   bool monthlyOBBear = mClose < mOpen && h1 >= MathMin(mClose, mOpen) && h1 <= MathMax(mClose, mOpen);

   // === GOD-TIER HYBRIDS ===
   bool wyckoffSpring   = lastSwingLow  > 0 && l1 < lastSwingLow  && c1 > lastSwingLow  && bullOBRetest && posVolDeltaAtZone;
   bool wyckoffTerminal = lastSwingHigh > 0 && h1 > lastSwingHigh && c1 < lastSwingHigh && bearOBRetest && negVolDeltaAtZone;
   bool threeDriveBull  = liqSweepBull && bullFVGEntry && bullOBRetest && oteBull;
   bool threeDriveBear  = liqSweepBear && bearFVGEntry && bearOBRetest && oteBear;

   // === BULL SCORING ===
   if(i_useOB         && bullOBRetest)       bScore += 15;
   if(i_useFVG        && bullFVGEntry)       bScore += 13;
   if(i_useBreaker    && bullBreakerRetest)  bScore += 11;
   if(i_useUnicorn    && bullUnicorn)        bScore += 18;
   if(i_useLiqSweep   && liqSweepBull)       bScore += 14;
   if(i_useOTE        && oteBull)            bScore += 12;
   if(i_useBPR        && bprBullRetest)      bScore += 9;
   if(i_useInducement && displacementUp)     bScore += 9;
   if(i_useMSS        && mssUp)              bScore += 11;
   if(i_useEngulf     && bullEngulfAtZone)   bScore += 8;
   if(i_useHammer     && hammerAtZone)       bScore += 8;
   if(i_useStar       && morningStar)        bScore += 7;
   if(i_useDoji       && dojiAtSup)          bScore += 6;
   if(i_useDivReg     && multiRegBullDiv)    bScore += 9;
   if(i_useDivHid     && hidBullDiv)         bScore += 8;
   if(i_useVolDelta   && posVolDeltaAtZone && imbalanceBull) bScore += 12;
   if(i_useFootPOC    && pocRejBull)         bScore += 7;
   if(i_useBBSqz      && bbBreakoutUp)       bScore += 7;
   if(i_useST         && stFlipOBBull)       bScore += 9;
   if(i_useEMA        && emaPullbackBull)    bScore += 7;
   if(i_useIchi       && ichiBreakBull)      bScore += 7;
   if(i_useHTFOB      && htfLTFBull)         bScore += 13;
   if(i_useKZ         && kzLiqBull)          bScore += 10;
   if(weeklyOBBull || monthlyOBBull)         bScore += 11;
   if(liqSweepBull && bullFVGEntry && bullOBRetest && oteBull) bScore += 16;
   if(wyckoffSpring)                         bScore += 15;
   if(threeDriveBull)                        bScore += 14;
   if(htfAlignBull)                          bScore += 10;

   // === BEAR SCORING ===
   if(i_useOB         && bearOBRetest)       beScore += 15;
   if(i_useFVG        && bearFVGEntry)       beScore += 13;
   if(i_useBreaker    && bearBreakerRetest)  beScore += 11;
   if(i_useUnicorn    && bearUnicorn)        beScore += 18;
   if(i_useLiqSweep   && liqSweepBear)       beScore += 14;
   if(i_useOTE        && oteBear)            beScore += 12;
   if(i_useBPR        && bprBearRetest)      beScore += 9;
   if(i_useInducement && displacementDown)   beScore += 9;
   if(i_useMSS        && mssDown)            beScore += 11;
   if(i_useEngulf     && bearEngulfAtZone)   beScore += 8;
   if(i_useHammer     && ssAtZone)           beScore += 8;
   if(i_useStar       && eveningStar)        beScore += 7;
   if(i_useDoji       && dojiAtRes)          beScore += 6;
   if(i_useDivReg     && multiRegBearDiv)    beScore += 9;
   if(i_useDivHid     && hidBearDiv)         beScore += 8;
   if(i_useVolDelta   && negVolDeltaAtZone && imbalanceBear) beScore += 12;
   if(i_useFootPOC    && pocRejBear)         beScore += 7;
   if(i_useBBSqz      && bbBreakoutDn)       beScore += 7;
   if(i_useST         && stFlipOBBear)       beScore += 9;
   if(i_useEMA        && emaPullbackBear)    beScore += 7;
   if(i_useIchi       && ichiBreakBear)      beScore += 7;
   if(i_useHTFOB      && htfLTFBear)         beScore += 13;
   if(i_useKZ         && kzLiqBear)          beScore += 10;
   if(weeklyOBBear || monthlyOBBear)         beScore += 11;
   if(liqSweepBear && bearFVGEntry && bearOBRetest && oteBear) beScore += 16;
   if(wyckoffTerminal)                       beScore += 15;
   if(threeDriveBear)                        beScore += 14;
   if(htfAlignBear)                          beScore += 10;

   // Normalize to 100
   double maxRaw = 260.0;
   bullScore = MathMin(100.0, MathRound(bScore  / maxRaw * 100.0));
   bearScore = MathMin(100.0, MathRound(beScore / maxRaw * 100.0));
}

//+------------------------------------------------------------------+
//| Trailing stop & break even management                            |
//+------------------------------------------------------------------+
void ManagePositions() {
   double atr = GetATR(14, 1);
   if(atr == 0) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != magicNumber) continue;
      double sl    = posInfo.StopLoss();
      double tp    = posInfo.TakeProfit();
      double open  = posInfo.PriceOpen();
      double cur   = posInfo.PriceCurrent();
      ulong  ticket = posInfo.Ticket();
      if(posInfo.PositionType() == POSITION_TYPE_BUY) {
         double newSL = cur - i_trailATRMult * atr;
         if(i_useBreakEven && cur >= open + i_beATRMult * atr && sl < open)
            trade.PositionModify(ticket, open + _Point, tp);
         else if(i_useTrailStop && newSL > sl && newSL < cur)
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
      } else {
         double newSL = cur + i_trailATRMult * atr;
         if(i_useBreakEven && cur <= open - i_beATRMult * atr && sl > open)
            trade.PositionModify(ticket, open - _Point, tp);
         else if(i_useTrailStop && newSL < sl && newSL > cur)
            trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Place trade                                                      |
//+------------------------------------------------------------------+
void PlaceTrade(bool isBuy) {
   if(!i_autoTrade) return;
   if(CountTrades() >= i_maxTrades) return;
   double atr  = GetATR(14, 1);
   if(atr == 0) return;
   double ask  = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid  = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double price = isBuy ? ask : bid;
   double sl   = isBuy ? price - i_slATRMult  * atr : price + i_slATRMult  * atr;
   double tp1  = isBuy ? price + i_tp1ATRMult * atr : price - i_tp1ATRMult * atr;
   double slPips = MathAbs(price - sl) / _Point;
   double lots   = CalcLotSize(slPips);
   sl  = NormalizeDouble(sl,  _Digits);
   tp1 = NormalizeDouble(tp1, _Digits);
   if(isBuy)
      trade.Buy(lots, Symbol(), price, sl, tp1, "GOD v7 BUY");
   else
      trade.Sell(lots, Symbol(), price, sl, tp1, "GOD v7 SELL");
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(20);

   atrHandle   = iATR(Symbol(), PERIOD_CURRENT, 14);
   rsiHandle   = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
   stochHandle = iStochastic(Symbol(), PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   ema8Handle  = iMA(Symbol(), PERIOD_CURRENT, 8,  0, MODE_EMA, PRICE_CLOSE);
   ema13Handle = iMA(Symbol(), PERIOD_CURRENT, 13, 0, MODE_EMA, PRICE_CLOSE);
   ema21Handle = iMA(Symbol(), PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
   ema34Handle = iMA(Symbol(), PERIOD_CURRENT, 34, 0, MODE_EMA, PRICE_CLOSE);
   ema55Handle = iMA(Symbol(), PERIOD_CURRENT, 55, 0, MODE_EMA, PRICE_CLOSE);
   bbHandle    = iBands(Symbol(), PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   macdHandle  = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);

   if(atrHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE ||
      ema21Handle == INVALID_HANDLE || bbHandle == INVALID_HANDLE) {
      Print("v7: Failed to create indicator handles");
      return INIT_FAILED;
   }

   bullOBCount = 0;
   bearOBCount = 0;
   fvgCount    = 0;
   structTrend = 0;
   prevSwingHigh = 0;
   prevSwingLow  = 0;

   // Seed historical structure immediately
   WarmUpHistory();

   Print("ULTIMATE GOD MODE EA v7 initialized on ", Symbol(),
         " | Magic:", magicNumber,
         " | StrongThr:", i_strongThr,
         " | ModThr:", i_modThr,
         " | GodThr:", i_godThr,
         " | TradeOnMod:", i_tradeOnMod);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(atrHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(stochHandle);
   IndicatorRelease(ema8Handle);
   IndicatorRelease(ema13Handle);
   IndicatorRelease(ema21Handle);
   IndicatorRelease(ema34Handle);
   IndicatorRelease(ema55Handle);
   IndicatorRelease(bbHandle);
   IndicatorRelease(macdHandle);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
   datetime curBarTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(curBarTime == lastBarTime) {
      ManagePositions();
      return;
   }
   lastBarTime = curBarTime;

   if(i_sessFilter && !InKillZone()) return;

   double bullScore = 0, bearScore = 0;
   CalcScores(bullScore, bearScore);

   bool bullDominates = bullScore > bearScore + 5;
   bool bearDominates = bearScore > bullScore + 5;

   double finalBullScore = bullDominates ? bullScore : 0;
   double finalBearScore = bearDominates ? bearScore : 0;

   bool godBuy    = finalBullScore >= i_godThr;
   bool godSell   = finalBearScore >= i_godThr;
   bool strongBuy  = finalBullScore >= i_strongThr && !godBuy;
   bool strongSell = finalBearScore >= i_strongThr && !godSell;
   bool modBuy    = finalBullScore >= i_modThr && finalBullScore < i_strongThr;
   bool modSell   = finalBearScore >= i_modThr && finalBearScore < i_strongThr;

   // Logging
   if(godBuy && i_showGod)
      Print("🌟 GOD BUY | Score:", finalBullScore, "/100 | ", Symbol(), " | ", TimeToString(TimeCurrent()));
   if(godSell && i_showGod)
      Print("🌟 GOD SELL | Score:", finalBearScore, "/100 | ", Symbol(), " | ", TimeToString(TimeCurrent()));
   if(strongBuy && i_showStrong)
      Print("🟢 STRONG BUY | Score:", finalBullScore, "/100");
   if(strongSell && i_showStrong)
      Print("🔴 STRONG SELL | Score:", finalBearScore, "/100");
   if(modBuy && i_showMod)
      Print("🟡 MOD BUY | Score:", finalBullScore, "/100");
   if(modSell && i_showMod)
      Print("🟠 MOD SELL | Score:", finalBearScore, "/100");

   // FIX v7: Also trade on Moderate signals if i_tradeOnMod is enabled
   if(godBuy || strongBuy || (i_tradeOnMod && modBuy))
      PlaceTrade(true);
   if(godSell || strongSell || (i_tradeOnMod && modSell))
      PlaceTrade(false);
}
//+------------------------------------------------------------------+

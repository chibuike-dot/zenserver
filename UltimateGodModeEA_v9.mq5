//+------------------------------------------------------------------+
//|  ULTIMATE v9 GOD MODE EA — ICT/SMC Confluence                   |
//|  Converted from Pine Script by Onwun                            |
//|  MQL5 Expert Advisor — Full Auto Trading                        |
//|  v9 FIXES:                                                       |
//|    - Bar-by-bar OB/FVG/structure — works in backtest from bar 1 |
//|    - No warm-up dependency                                       |
//|    - barCount guard: skips scoring until enough bars seen        |
//|    - Relaxed thresholds, moderate signal trading                 |
//|    - SL ATR 2.5, pivot lookback 3                               |
//|    - Fixed: duplicate variable declarations (rng1, l2, delta)   |
//+------------------------------------------------------------------+
#property copyright "ULTIMATE GOD MODE EA v9"
#property version   "9.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "⚙️ Core Settings"
input bool   i_showStrong    = true;
input bool   i_showMod       = true;
input bool   i_showGod       = true;
input bool   i_autoTrade     = true;
input double i_lotSize       = 0.01;
input double i_riskPercent   = 1.0;
input int    i_maxTrades     = 3;

input group "📊 Score Thresholds"
input int    i_godThr        = 80;
input int    i_strongThr     = 55;
input int    i_modThr        = 35;
input bool   i_tradeOnMod    = true;

input group "🕐 Multi-Timeframe"
input ENUM_TIMEFRAMES i_tf1  = PERIOD_H1;
input ENUM_TIMEFRAMES i_tf2  = PERIOD_H4;
input ENUM_TIMEFRAMES i_tf3  = PERIOD_D1;
input bool   i_useTF1        = true;
input bool   i_useTF2        = true;
input bool   i_useTF3        = true;

input group "🏦 ICT / SMC Modules"
input bool   i_useOB         = true;
input bool   i_useFVG        = true;
input bool   i_useBreaker    = true;
input bool   i_useUnicorn    = true;
input bool   i_useLiqSweep   = true;
input bool   i_useOTE        = true;
input bool   i_useBPR        = true;
input bool   i_useInducement = true;
input bool   i_useMSS        = true;
input bool   i_useKZ         = true;
input bool   i_useHTFOB      = true;

input group "📈 Classical TA"
input bool   i_useEngulf     = true;
input bool   i_useHammer     = true;
input bool   i_useStar       = true;
input bool   i_useDoji       = true;
input bool   i_useDivReg     = true;
input bool   i_useDivHid     = true;
input bool   i_useBBSqz      = true;
input bool   i_useST         = true;
input bool   i_useEMA        = true;
input bool   i_useIchi       = true;

input group "📦 Volume"
input bool   i_useVolDelta   = true;
input bool   i_useFootPOC    = true;

input group "💰 Trade Management"
input double i_slATRMult     = 2.5;
input double i_tp1ATRMult    = 2.0;
input bool   i_useTrailStop  = true;
input double i_trailATRMult  = 1.0;
input bool   i_useBreakEven  = true;
input double i_beATRMult     = 1.5;

input group "🕐 Session Filters"
input bool   i_sessFilter    = false;
input int    i_londonStart   = 7;
input int    i_londonEnd     = 10;
input int    i_nyStart       = 13;
input int    i_nyEnd         = 17;

input int    i_pivLen        = 3;
input int    i_minBars       = 20;   // Min bars before trading starts

//+------------------------------------------------------------------+
//| STRUCTS                                                          |
//+------------------------------------------------------------------+
#define MAX_OB  10
#define MAX_FVG 15

struct OBZone {
   double top, bot;
   bool   mitigated;
};

struct FVGZone {
   double top, bot;
   bool   bullish, filled;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
OBZone  bullOBs[MAX_OB],  bearOBs[MAX_OB];
FVGZone fvgZones[MAX_FVG];
int     bullOBCount = 0, bearOBCount = 0, fvgCount = 0;

int     structTrend   = 0;
double  prevSwingHigh = 0, prevSwingLow = 0;
double  lastSwingHigh = 0, lastSwingLow = 0;

double  lastRsiHigh = 0, lastRsiLow = 0;
double  lastPriceHigh = 0, lastPriceLow = 0;

int     atrHandle, rsiHandle, stochHandle;
int     ema8h, ema13h, ema21h, ema34h, ema55h, bbHandle, macdHandle;

datetime lastBarTime  = 0;
int      barCount     = 0;
int      magicNumber  = 20260901;

// Supertrend state
double   stFinal = 0;
int      stDir   = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double GetATR(int shift=1) {
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(atrHandle,0,shift,1,b)<=0) return 0.0001;
   return b[0];
}
double GetRSI(int shift=1) {
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(rsiHandle,0,shift,1,b)<=0) return 50;
   return b[0];
}
double GetEMA(int h, int shift=1) {
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(h,0,shift,1,b)<=0) return 0;
   return b[0];
}
void GetBB(double &u, double &l, double &mid, int shift=1) {
   double bu[],bl[],bm[];
   ArraySetAsSeries(bu,true); ArraySetAsSeries(bl,true); ArraySetAsSeries(bm,true);
   CopyBuffer(bbHandle,1,shift,1,bu);
   CopyBuffer(bbHandle,2,shift,1,bl);
   CopyBuffer(bbHandle,0,shift,1,bm);
   u=bu[0]; l=bl[0]; mid=bm[0];
}
double GetStochK(int shift=1) {
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(stochHandle,0,shift,1,b)<=0) return 50;
   return b[0];
}
int GetHTFBias(ENUM_TIMEFRAMES tf) {
   double c=iClose(Symbol(),tf,1), o=iOpen(Symbol(),tf,1);
   if(c==0||o==0) return 0;
   return c>o?1:c<o?-1:0;
}
bool InKillZone() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int h=dt.hour;
   return (h>=i_londonStart&&h<i_londonEnd)||(h>=i_nyStart&&h<i_nyEnd);
}
int CountTrades() {
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
      if(posInfo.SelectByIndex(i)&&posInfo.Symbol()==Symbol()&&posInfo.Magic()==magicNumber) n++;
   return n;
}
double CalcLots(double slPips) {
   if(slPips<=0) return i_lotSize;
   double tv=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*i_riskPercent/100.0;
   double lots=risk/(slPips/ts*tv);
   double mn=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   lots=MathFloor(lots/st)*st;
   return MathMax(mn,MathMin(mx,lots));
}

//+------------------------------------------------------------------+
//| Pivot detection (uses closed bars only — safe in backtest)       |
//+------------------------------------------------------------------+
double PivHigh(int len, int shift) {
   double p=iHigh(Symbol(),PERIOD_CURRENT,len+shift);
   if(p==0) return 0;
   for(int i=shift;i<2*len+1+shift;i++) {
      if(i==len+shift) continue;
      if(iHigh(Symbol(),PERIOD_CURRENT,i)>=p) return 0;
   }
   return p;
}
double PivLow(int len, int shift) {
   double p=iLow(Symbol(),PERIOD_CURRENT,len+shift);
   if(p==0) return 0;
   for(int i=shift;i<2*len+1+shift;i++) {
      if(i==len+shift) continue;
      if(iLow(Symbol(),PERIOD_CURRENT,i)<=p) return 0;
   }
   return p;
}

//+------------------------------------------------------------------+
//| Add OB zone                                                      |
//+------------------------------------------------------------------+
void AddBullOB(double top, double bot) {
   if(top<=bot) return;
   OBZone ob; ob.top=top; ob.bot=bot; ob.mitigated=false;
   if(bullOBCount<MAX_OB) { for(int j=bullOBCount;j>0;j--) bullOBs[j]=bullOBs[j-1]; bullOBs[0]=ob; bullOBCount++; }
   else                   { for(int j=MAX_OB-1;j>0;j--)   bullOBs[j]=bullOBs[j-1]; bullOBs[0]=ob; }
}
void AddBearOB(double top, double bot) {
   if(top<=bot) return;
   OBZone ob; ob.top=top; ob.bot=bot; ob.mitigated=false;
   if(bearOBCount<MAX_OB) { for(int j=bearOBCount;j>0;j--) bearOBs[j]=bearOBs[j-1]; bearOBs[0]=ob; bearOBCount++; }
   else                   { for(int j=MAX_OB-1;j>0;j--)    bearOBs[j]=bearOBs[j-1]; bearOBs[0]=ob; }
}

//+------------------------------------------------------------------+
//| Add FVG zone                                                     |
//+------------------------------------------------------------------+
void AddFVG(double top, double bot, bool bull) {
   if(top<=bot) return;
   FVGZone f; f.top=top; f.bot=bot; f.bullish=bull; f.filled=false;
   if(fvgCount<MAX_FVG) { for(int j=fvgCount;j>0;j--) fvgZones[j]=fvgZones[j-1]; fvgZones[0]=f; fvgCount++; }
   else                 { for(int j=MAX_FVG-1;j>0;j--) fvgZones[j]=fvgZones[j-1]; fvgZones[0]=f; }
}

//+------------------------------------------------------------------+
//| Update structure on each new bar — core v8 fix                  |
//+------------------------------------------------------------------+
void UpdateStructure() {
   // Only use confirmed closed bars (shift >= 1)
   double pH = PivHigh(i_pivLen, i_pivLen);
   double pL = PivLow(i_pivLen,  i_pivLen);

   // BOS / CHoCH
   bool bosUp=false, bosDown=false, chochUp=false, chochDown=false;
   if(pH>0 && prevSwingHigh>0 && pH>prevSwingHigh) {
      if(structTrend==1) bosUp=true; else chochUp=true;
      structTrend=1;
   }
   if(pL>0 && prevSwingLow>0 && pL<prevSwingLow) {
      if(structTrend==-1) bosDown=true; else chochDown=true;
      structTrend=-1;
   }
   if(pH>0) { prevSwingHigh=pH; lastSwingHigh=pH; }
   if(pL>0) { prevSwingLow=pL;  lastSwingLow=pL;  }

   // Build OBs on BOS/CHoCH
   if(bosUp||chochUp) {
      // Last bearish candle before the break = bull OB
      for(int i=2;i<20;i++) {
         double c=iClose(Symbol(),PERIOD_CURRENT,i);
         double o=iOpen(Symbol(), PERIOD_CURRENT,i);
         if(c<o) { AddBullOB(MathMax(o,c), MathMin(o,c)); break; }
      }
   }
   if(bosDown||chochDown) {
      // Last bullish candle before the break = bear OB
      for(int i=2;i<20;i++) {
         double c=iClose(Symbol(),PERIOD_CURRENT,i);
         double o=iOpen(Symbol(), PERIOD_CURRENT,i);
         if(c>o) { AddBearOB(MathMax(o,c), MathMin(o,c)); break; }
      }
   }

   // Build FVGs every bar (3-candle gap)
   double l1=iLow(Symbol(), PERIOD_CURRENT,1);
   double h3=iHigh(Symbol(),PERIOD_CURRENT,3);
   double h1=iHigh(Symbol(),PERIOD_CURRENT,1);
   double l3=iLow(Symbol(), PERIOD_CURRENT,3);
   if(l1>h3) AddFVG(l1,h3,true);
   if(h1<l3) AddFVG(l3,h1,false);

   // Mitigate OBs
   double c1=iClose(Symbol(),PERIOD_CURRENT,1);
   for(int i=0;i<bullOBCount;i++) if(!bullOBs[i].mitigated && c1<bullOBs[i].bot) bullOBs[i].mitigated=true;
   for(int i=0;i<bearOBCount;i++) if(!bearOBs[i].mitigated && c1>bearOBs[i].top) bearOBs[i].mitigated=true;

   // Fill FVGs
   double hh1=iHigh(Symbol(),PERIOD_CURRENT,1);
   double ll1=iLow(Symbol(), PERIOD_CURRENT,1);
   for(int i=0;i<fvgCount;i++) {
      if(!fvgZones[i].filled) {
         if(fvgZones[i].bullish  && ll1<=fvgZones[i].top) fvgZones[i].filled=true;
         if(!fvgZones[i].bullish && hh1>=fvgZones[i].bot) fvgZones[i].filled=true;
      }
   }
}

//+------------------------------------------------------------------+
//| Supertrend (stateful, called once per bar)                       |
//+------------------------------------------------------------------+
void UpdateSupertrend() {
   double atr=GetATR(1);
   double hl2=(iHigh(Symbol(),PERIOD_CURRENT,1)+iLow(Symbol(),PERIOD_CURRENT,1))/2.0;
   double upper=hl2-3.0*atr;
   double lower=hl2+3.0*atr;
   double c=iClose(Symbol(),PERIOD_CURRENT,1);
   double cprev=iClose(Symbol(),PERIOD_CURRENT,2);
   if(stFinal==0){stFinal=upper;stDir=1;}
   double nf;
   if(cprev>stFinal) nf=MathMax(upper,stFinal);
   else              nf=MathMin(lower,stFinal);
   stDir  = c>nf ? 1 : -1;
   stFinal= nf;
}

//+------------------------------------------------------------------+
//| SCORING                                                          |
//+------------------------------------------------------------------+
void CalcScores(double &bullScore, double &bearScore) {
   double bS=0, beS=0;

   double c1=iClose(Symbol(),PERIOD_CURRENT,1);
   double c2=iClose(Symbol(),PERIOD_CURRENT,2);
   double c3=iClose(Symbol(),PERIOD_CURRENT,3);
   double o1=iOpen(Symbol(), PERIOD_CURRENT,1);
   double o2=iOpen(Symbol(), PERIOD_CURRENT,2);
   double o3=iOpen(Symbol(), PERIOD_CURRENT,3);
   double h1=iHigh(Symbol(), PERIOD_CURRENT,1);
   double h2=iHigh(Symbol(), PERIOD_CURRENT,2);
   double l1=iLow(Symbol(),  PERIOD_CURRENT,1);
   double candleL2=iLow(Symbol(),  PERIOD_CURRENT,2);

   double pH=PivHigh(i_pivLen,i_pivLen);
   double pL=PivLow(i_pivLen, i_pivLen);

   // --- OB Retest ---
   bool bullOBRetest=false, bearOBRetest=false;
   for(int i=0;i<bullOBCount;i++)
      if(!bullOBs[i].mitigated && l1<=bullOBs[i].top && l1>=bullOBs[i].bot && c1>bullOBs[i].bot)
         bullOBRetest=true;
   for(int i=0;i<bearOBCount;i++)
      if(!bearOBs[i].mitigated && h1>=bearOBs[i].bot && h1<=bearOBs[i].top && c1<bearOBs[i].top)
         bearOBRetest=true;

   // --- FVG Entry ---
   bool bullFVGEntry=false, bearFVGEntry=false;
   for(int i=0;i<fvgCount;i++) {
      if(!fvgZones[i].filled) {
         if(fvgZones[i].bullish  && l1<=fvgZones[i].top && l1>=fvgZones[i].bot && c1>fvgZones[i].bot) bullFVGEntry=true;
         if(!fvgZones[i].bullish && h1>=fvgZones[i].bot && h1<=fvgZones[i].top && c1<fvgZones[i].top) bearFVGEntry=true;
      }
   }

   // --- Breaker ---
   bool bullBreaker=false, bearBreaker=false;
   for(int i=0;i<bullOBCount;i++)
      if(bullOBs[i].mitigated && l1<=bullOBs[i].top && l1>=bullOBs[i].bot && c1>bullOBs[i].top) bullBreaker=true;
   for(int i=0;i<bearOBCount;i++)
      if(bearOBs[i].mitigated && h1>=bearOBs[i].bot && h1<=bearOBs[i].top && c1<bearOBs[i].bot) bearBreaker=true;

   // --- Unicorn ---
   bool bullUnicorn = bullFVGEntry && bullBreaker;
   bool bearUnicorn = bearFVGEntry && bearBreaker;

   // --- Liq Sweep (relaxed — no same-bar BOS required) ---
   bool liqBull = lastSwingLow>0  && l1<lastSwingLow  && c1>lastSwingLow;
   bool liqBear = lastSwingHigh>0 && h1>lastSwingHigh && c1<lastSwingHigh;

   // --- OTE ---
   bool oteBull=false, oteBear=false;
   if(lastSwingHigh>0 && lastSwingLow>0 && lastSwingHigh>lastSwingLow) {
      double rng=lastSwingHigh-lastSwingLow;
      oteBull = l1<=(lastSwingHigh-0.618*rng) && l1>=(lastSwingHigh-0.786*rng) && structTrend==1;
      oteBear = h1>=(lastSwingLow +0.618*rng) && h1<=(lastSwingLow +0.786*rng) && structTrend==-1;
   }

   // --- BPR ---
   bool bprBull=false, bprBear=false;
   if(fvgCount>=2) {
      double ot=MathMin(fvgZones[0].top,fvgZones[1].top);
      double ob=MathMax(fvgZones[0].bot,fvgZones[1].bot);
      if(ot>ob && fvgZones[0].bullish!=fvgZones[1].bullish) {
         bprBull = l1<=ot && l1>=ob && structTrend==1;
         bprBear = h1>=ob && h1<=ot && structTrend==-1;
      }
   }

   // --- Displacement ---
   double ts=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   double eqH= MathAbs(h2-iHigh(Symbol(),PERIOD_CURRENT,4))<ts*5 ? h2 : 0;
   double eqL= MathAbs(candleL2-iLow(Symbol(), PERIOD_CURRENT,4))<ts*5 ? candleL2 : 0;
   double dispRng1=h1-l1;
   bool dispUp  = eqL>0 && l1<eqL && c1>eqL && dispRng1>0 && (c1-o1)>dispRng1*0.6;
   bool dispDown= eqH>0 && h1>eqH && c1<eqH && dispRng1>0 && (o1-c1)>dispRng1*0.6;

   // --- MSS/CHoCH (from structTrend changes, tracked in UpdateStructure) ---
   // Use pivot breaks as proxy
   bool mssUp   = pH>0 && prevSwingHigh>0 && pH>prevSwingHigh && structTrend!=1;
   bool mssDown = pL>0 && prevSwingLow>0  && pL<prevSwingLow  && structTrend!=-1;

   // --- Kill zone ---
   bool inKZ=InKillZone();
   bool kzBull=inKZ&&liqBull, kzBear=inKZ&&liqBear;

   // --- Volume ---
   double vol1=(double)iVolume(Symbol(),PERIOD_CURRENT,1);
   double avgVol=0;
   for(int i=1;i<=20;i++) avgVol+=(double)iVolume(Symbol(),PERIOD_CURRENT,i);
   avgVol/=20.0;
   double delta=0, deltaAvg=0;
   for(int i=1;i<=14;i++) {
      double vv=(double)iVolume(Symbol(),PERIOD_CURRENT,i);
      double vc=iClose(Symbol(),PERIOD_CURRENT,i), vo=iOpen(Symbol(),PERIOD_CURRENT,i);
      double vh=iHigh(Symbol(),PERIOD_CURRENT,i),  vlo=iLow(Symbol(),PERIOD_CURRENT,i);
      double vr=vh-vlo; if(vr==0) continue;
      double bv=vc>vo?vv:vv*((vc-vlo)/vr);
      double d=bv-(vv-bv);
      if(i==1) delta=d;
      deltaAvg+=d;
   }
   deltaAvg/=14.0;
   bool imbBull = delta>deltaAvg*1.1 && vol1>avgVol*1.3;
   bool imbBear = delta<deltaAvg*-1.1 && vol1>avgVol*1.3;
   bool posVol  = (delta>deltaAvg&&delta>0) && (bullFVGEntry||bullOBRetest);
   bool negVol  = (delta<deltaAvg&&delta<0) && (bearFVGEntry||bearOBRetest);
   bool volSpike= vol1>avgVol*1.3;

   // --- POC (VWAP proxy = EMA21) ---
   double vwap=GetEMA(ema21h,1);
   bool pocBull = l1<=vwap && c1>vwap && structTrend==1;
   bool pocBear = h1>=vwap && c1<vwap && structTrend==-1;

   // --- RSI Divergence ---
   double rsiPL = pL>0 ? GetRSI(i_pivLen*2) : 0;
   double rsiPH = pH>0 ? GetRSI(i_pivLen*2) : 0;
   bool regBullDiv = pL>0 && lastPriceLow>0  && pL<lastPriceLow  && rsiPL>lastRsiLow;
   bool regBearDiv = pH>0 && lastPriceHigh>0 && pH>lastPriceHigh && rsiPH<lastRsiHigh;
   bool hidBullDiv = pL>0 && lastPriceLow>0  && pL>lastPriceLow  && rsiPL<lastRsiLow;
   bool hidBearDiv = pH>0 && lastPriceHigh>0 && pH<lastPriceHigh && rsiPH>lastRsiHigh;
   if(pL>0){lastPriceLow=pL;  lastRsiLow=GetRSI(i_pivLen);}
   if(pH>0){lastPriceHigh=pH; lastRsiHigh=GetRSI(i_pivLen);}

   // --- EMA Ribbon ---
   double e8=GetEMA(ema8h,1), e13=GetEMA(ema13h,1), e21=GetEMA(ema21h,1);
   double e34=GetEMA(ema34h,1), e55=GetEMA(ema55h,1);
   bool ribBull = e8>e13&&e13>e21&&e21>e34&&e34>e55;
   bool ribBear = e8<e13&&e13<e21&&e21<e34&&e34<e55;
   bool emaBull = ribBull && l1<=e21 && c1>e21 && structTrend==1;
   bool emaBear = ribBear && h1>=e21 && c1<e21 && structTrend==-1;

   // --- BB Squeeze ---
   double bbu,bbl,bbm;
   GetBB(bbu,bbl,bbm,1);
   double bbw=bbu-bbl, bbwAvg=0;
   for(int i=1;i<=20;i++){double bu,bl,bm; GetBB(bu,bl,bm,i); bbwAvg+=bu-bl;} bbwAvg/=20.0;
   double bbU2,bbL2,bbM2; GetBB(bbU2,bbL2,bbM2,2);
   bool sqz2=(bbU2-bbL2)<bbwAvg*0.7;
   bool bbUp = sqz2&&c1>bbu&&ribBull;
   bool bbDn = sqz2&&c1<bbl&&ribBear;

   // --- Supertrend ---
   bool stFlipBull = stDir==1;   // Already updated in UpdateSupertrend()
   bool stFlipBear = stDir==-1;
   bool stOBBull   = stFlipBull && bullOBRetest;
   bool stOBBear   = stFlipBear && bearOBRetest;

   // --- Ichimoku ---
   double cH=0,cL=99e9,bH=0,bL=99e9;
   for(int i=1;i<=9; i++){cH=MathMax(cH,iHigh(Symbol(),PERIOD_CURRENT,i)); cL=MathMin(cL,iLow(Symbol(),PERIOD_CURRENT,i));}
   for(int i=1;i<=26;i++){bH=MathMax(bH,iHigh(Symbol(),PERIOD_CURRENT,i)); bL=MathMin(bL,iLow(Symbol(),PERIOD_CURRENT,i));}
   double conv=(cH+cL)/2, base=(bH+bL)/2;
   double lb52H=0,lb52L=99e9;
   for(int i=1;i<=52;i++){lb52H=MathMax(lb52H,iHigh(Symbol(),PERIOD_CURRENT,i)); lb52L=MathMin(lb52L,iLow(Symbol(),PERIOD_CURRENT,i));}
   double leadA=(conv+base)/2, leadB=(lb52H+lb52L)/2;
   double cH2=0,cL2=99e9,bH2=0,bL2=99e9;
   for(int i=2;i<=10;i++){cH2=MathMax(cH2,iHigh(Symbol(),PERIOD_CURRENT,i)); cL2=MathMin(cL2,iLow(Symbol(),PERIOD_CURRENT,i));}
   for(int i=2;i<=27;i++){bH2=MathMax(bH2,iHigh(Symbol(),PERIOD_CURRENT,i)); bL2=MathMin(bL2,iLow(Symbol(),PERIOD_CURRENT,i));}
   double convP=(cH2+cL2)/2, baseP=(bH2+bL2)/2;
   bool tkUp  = conv>base  && convP<=baseP;
   bool tkDn  = conv<base  && convP>=baseP;
   bool clBull= leadA>leadB, clBear=leadA<leadB;
   bool ichiBull = tkUp && clBull && c1>MathMax(leadA,leadB);
   bool ichiBear = tkDn && clBear && c1<MathMin(leadA,leadB);

   // --- Candle Patterns ---
   bool bullEngulf = c1>o1&&c2<o2&&c1>o2&&o1<c2;
   bool bearEngulf = c1<o1&&c2>o2&&c1<o2&&o1>c2;
   bool bullEngZ   = bullEngulf&&(bullOBRetest||bullFVGEntry);
   bool bearEngZ   = bearEngulf&&(bearOBRetest||bearFVGEntry);
   double candleRng1=h1-l1, body1=MathAbs(c1-o1);
   double uwk=h1-MathMax(c1,o1), lwk=MathMin(c1,o1)-l1;
   bool isHmr = candleRng1>0&&lwk>=body1*2&&uwk<body1*0.5&&c1>o1;
   bool isSS  = candleRng1>0&&uwk>=body1*2&&lwk<body1*0.5&&c1<o1;
   bool hmrZ  = isHmr&&volSpike&&(bullOBRetest||bullFVGEntry);
   bool ssZ   = isSS &&volSpike&&(bearOBRetest||bearFVGEntry);
   double c4=iClose(Symbol(),PERIOD_CURRENT,4), o4=iOpen(Symbol(),PERIOD_CURRENT,4);
   double h3c=iHigh(Symbol(),PERIOD_CURRENT,3)-iLow(Symbol(),PERIOD_CURRENT,3);
   bool mornStar = c4<o4&&MathAbs(c3-o3)<h3c*0.3&&c2>o2&&c2>(o4+c4)/2;
   bool eveStar  = c4>o4&&MathAbs(c3-o3)<h3c*0.3&&c2<o2&&c2<(o4+c4)/2;
   bool isDoji   = candleRng1>0&&body1<candleRng1*0.15;
   bool dojiSup  = isDoji&&(bullOBRetest||bullFVGEntry||bprBull);
   bool dojiRes  = isDoji&&(bearOBRetest||bearFVGEntry||bprBear);

   // --- HTF Bias ---
   int htfB=0,htfBr=0;
   if(i_useTF1){int b=GetHTFBias(i_tf1); if(b>0)htfB++; else if(b<0)htfBr++;}
   if(i_useTF2){int b=GetHTFBias(i_tf2); if(b>0)htfB++; else if(b<0)htfBr++;}
   if(i_useTF3){int b=GetHTFBias(i_tf3); if(b>0)htfB++; else if(b<0)htfBr++;}
   bool htfBull = htfB>htfBr, htfBear = htfBr>htfB;
   bool htfLTFB = htfBull && structTrend==1;
   bool htfLTFBr= htfBear && structTrend==-1;

   // --- Weekly/Monthly OB ---
   double wC=iClose(Symbol(),PERIOD_W1,1),  wO=iOpen(Symbol(),PERIOD_W1,1);
   double mC=iClose(Symbol(),PERIOD_MN1,1), mO=iOpen(Symbol(),PERIOD_MN1,1);
   bool wkBull = wC>wO && l1<=MathMax(wC,wO) && l1>=MathMin(wC,wO);
   bool wkBear = wC<wO && h1>=MathMin(wC,wO) && h1<=MathMax(wC,wO);
   bool mnBull = mC>mO && l1<=MathMax(mC,mO) && l1>=MathMin(mC,mO);
   bool mnBear = mC<mO && h1>=MathMin(mC,mO) && h1<=MathMax(mC,mO);

   // --- God-tier combos ---
   bool wyckoffSpr  = lastSwingLow>0  && l1<lastSwingLow  && c1>lastSwingLow  && bullOBRetest && posVol;
   bool wyckoffTerm = lastSwingHigh>0 && h1>lastSwingHigh && c1<lastSwingHigh && bearOBRetest && negVol;
   bool threeDrvB   = liqBull && bullFVGEntry && bullOBRetest && oteBull;
   bool threeDrvBr  = liqBear && bearFVGEntry && bearOBRetest && oteBear;

   // === BULL SCORE ===
   if(i_useOB        && bullOBRetest) bS+=15;
   if(i_useFVG       && bullFVGEntry) bS+=13;
   if(i_useBreaker   && bullBreaker)  bS+=11;
   if(i_useUnicorn   && bullUnicorn)  bS+=18;
   if(i_useLiqSweep  && liqBull)      bS+=14;
   if(i_useOTE       && oteBull)      bS+=12;
   if(i_useBPR       && bprBull)      bS+=9;
   if(i_useInducement&& dispUp)       bS+=9;
   if(i_useMSS       && mssUp)        bS+=11;
   if(i_useEngulf    && bullEngZ)     bS+=8;
   if(i_useHammer    && hmrZ)         bS+=8;
   if(i_useStar      && mornStar)     bS+=7;
   if(i_useDoji      && dojiSup)      bS+=6;
   if(i_useDivReg    && regBullDiv)   bS+=9;
   if(i_useDivHid    && hidBullDiv)   bS+=8;
   if(i_useVolDelta  && posVol&&imbBull) bS+=12;
   if(i_useFootPOC   && pocBull)      bS+=7;
   if(i_useBBSqz     && bbUp)         bS+=7;
   if(i_useST        && stOBBull)     bS+=9;
   if(i_useEMA       && emaBull)      bS+=7;
   if(i_useIchi      && ichiBull)     bS+=7;
   if(i_useHTFOB     && htfLTFB)      bS+=13;
   if(i_useKZ        && kzBull)       bS+=10;
   if(wkBull||mnBull)                 bS+=11;
   if(liqBull&&bullFVGEntry&&bullOBRetest&&oteBull) bS+=16;
   if(wyckoffSpr)                     bS+=15;
   if(threeDrvB)                      bS+=14;
   if(htfBull)                        bS+=10;

   // === BEAR SCORE ===
   if(i_useOB        && bearOBRetest) beS+=15;
   if(i_useFVG       && bearFVGEntry) beS+=13;
   if(i_useBreaker   && bearBreaker)  beS+=11;
   if(i_useUnicorn   && bearUnicorn)  beS+=18;
   if(i_useLiqSweep  && liqBear)      beS+=14;
   if(i_useOTE       && oteBear)      beS+=12;
   if(i_useBPR       && bprBear)      beS+=9;
   if(i_useInducement&& dispDown)     beS+=9;
   if(i_useMSS       && mssDown)      beS+=11;
   if(i_useEngulf    && bearEngZ)     beS+=8;
   if(i_useHammer    && ssZ)          beS+=8;
   if(i_useStar      && eveStar)      beS+=7;
   if(i_useDoji      && dojiRes)      beS+=6;
   if(i_useDivReg    && regBearDiv)   beS+=9;
   if(i_useDivHid    && hidBearDiv)   beS+=8;
   if(i_useVolDelta  && negVol&&imbBear) beS+=12;
   if(i_useFootPOC   && pocBear)      beS+=7;
   if(i_useBBSqz     && bbDn)         beS+=7;
   if(i_useST        && stOBBear)     beS+=9;
   if(i_useEMA       && emaBear)      beS+=7;
   if(i_useIchi      && ichiBear)     beS+=7;
   if(i_useHTFOB     && htfLTFBr)     beS+=13;
   if(i_useKZ        && kzBear)       beS+=10;
   if(wkBear||mnBear)                 beS+=11;
   if(liqBear&&bearFVGEntry&&bearOBRetest&&oteBear) beS+=16;
   if(wyckoffTerm)                    beS+=15;
   if(threeDrvBr)                     beS+=14;
   if(htfBear)                        beS+=10;

   double maxRaw=260.0;
   bullScore=MathMin(100.0,MathRound(bS/maxRaw*100.0));
   bearScore=MathMin(100.0,MathRound(beS/maxRaw*100.0));
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManagePositions() {
   double atr=GetATR(1);
   if(atr==0) return;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()!=Symbol()||posInfo.Magic()!=magicNumber) continue;
      double sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double open=posInfo.PriceOpen(), cur=posInfo.PriceCurrent();
      ulong ticket=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY) {
         double nsl=cur-i_trailATRMult*atr;
         if(i_useBreakEven && cur>=open+i_beATRMult*atr && sl<open)
            trade.PositionModify(ticket,open+_Point,tp);
         else if(i_useTrailStop && nsl>sl && nsl<cur)
            trade.PositionModify(ticket,NormalizeDouble(nsl,_Digits),tp);
      } else {
         double nsl=cur+i_trailATRMult*atr;
         if(i_useBreakEven && cur<=open-i_beATRMult*atr && sl>open)
            trade.PositionModify(ticket,open-_Point,tp);
         else if(i_useTrailStop && nsl<sl && nsl>cur)
            trade.PositionModify(ticket,NormalizeDouble(nsl,_Digits),tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Place trade                                                      |
//+------------------------------------------------------------------+
void PlaceTrade(bool isBuy) {
   if(!i_autoTrade) return;
   if(CountTrades()>=i_maxTrades) return;
   double atr=GetATR(1); if(atr==0) return;
   double ask=SymbolInfoDouble(Symbol(),SYMBOL_ASK);
   double bid=SymbolInfoDouble(Symbol(),SYMBOL_BID);
   double price=isBuy?ask:bid;
   double sl=isBuy?price-i_slATRMult*atr:price+i_slATRMult*atr;
   double tp=isBuy?price+i_tp1ATRMult*atr:price-i_tp1ATRMult*atr;
   double slPips=MathAbs(price-sl)/_Point;
   double lots=CalcLots(slPips);
   sl=NormalizeDouble(sl,_Digits); tp=NormalizeDouble(tp,_Digits);
   if(isBuy) trade.Buy(lots,Symbol(),price,sl,tp,"GOD v9 BUY");
   else      trade.Sell(lots,Symbol(),price,sl,tp,"GOD v9 SELL");
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(20);

   atrHandle  = iATR(Symbol(),PERIOD_CURRENT,14);
   rsiHandle  = iRSI(Symbol(),PERIOD_CURRENT,14,PRICE_CLOSE);
   stochHandle= iStochastic(Symbol(),PERIOD_CURRENT,14,3,3,MODE_SMA,STO_LOWHIGH);
   ema8h      = iMA(Symbol(),PERIOD_CURRENT,8, 0,MODE_EMA,PRICE_CLOSE);
   ema13h     = iMA(Symbol(),PERIOD_CURRENT,13,0,MODE_EMA,PRICE_CLOSE);
   ema21h     = iMA(Symbol(),PERIOD_CURRENT,21,0,MODE_EMA,PRICE_CLOSE);
   ema34h     = iMA(Symbol(),PERIOD_CURRENT,34,0,MODE_EMA,PRICE_CLOSE);
   ema55h     = iMA(Symbol(),PERIOD_CURRENT,55,0,MODE_EMA,PRICE_CLOSE);
   bbHandle   = iBands(Symbol(),PERIOD_CURRENT,20,0,2.0,PRICE_CLOSE);
   macdHandle = iMACD(Symbol(),PERIOD_CURRENT,12,26,9,PRICE_CLOSE);

   if(atrHandle==INVALID_HANDLE||rsiHandle==INVALID_HANDLE||ema21h==INVALID_HANDLE||bbHandle==INVALID_HANDLE) {
      Print("v8: indicator init failed"); return INIT_FAILED;
   }

   // Reset all state
   bullOBCount=0; bearOBCount=0; fvgCount=0;
   structTrend=0; prevSwingHigh=0; prevSwingLow=0;
   lastSwingHigh=0; lastSwingLow=0;
   lastRsiHigh=0; lastRsiLow=0; lastPriceHigh=0; lastPriceLow=0;
   barCount=0; stFinal=0; stDir=0;

   Print("ULTIMATE GOD MODE EA v9 initialized | Magic:",magicNumber,
         " | GodThr:",i_godThr," StrongThr:",i_strongThr," ModThr:",i_modThr,
         " | TradeOnMod:",i_tradeOnMod," | MinBars:",i_minBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(atrHandle); IndicatorRelease(rsiHandle);
   IndicatorRelease(stochHandle); IndicatorRelease(ema8h);
   IndicatorRelease(ema13h); IndicatorRelease(ema21h);
   IndicatorRelease(ema34h); IndicatorRelease(ema55h);
   IndicatorRelease(bbHandle); IndicatorRelease(macdHandle);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
   datetime cur=iTime(Symbol(),PERIOD_CURRENT,0);
   if(cur==lastBarTime) { ManagePositions(); return; }
   lastBarTime=cur;
   barCount++;

   // Always update structure on every new bar (bar-by-bar — v8 core fix)
   UpdateStructure();
   UpdateSupertrend();

   // Wait for enough bars to build structure before trading
   if(barCount < i_minBars) return;

   if(i_sessFilter && !InKillZone()) return;

   double bullScore=0, bearScore=0;
   CalcScores(bullScore,bearScore);

   bool bullDom = bullScore > bearScore+5;
   bool bearDom = bearScore > bullScore+5;
   double fB = bullDom ? bullScore : 0;
   double fBr= bearDom ? bearScore : 0;

   bool godBuy    = fB>=i_godThr;
   bool godSell   = fBr>=i_godThr;
   bool strBuy    = fB>=i_strongThr && !godBuy;
   bool strSell   = fBr>=i_strongThr && !godSell;
   bool modBuy    = fB>=i_modThr && fB<i_strongThr;
   bool modSell   = fBr>=i_modThr && fBr<i_strongThr;

   if(godBuy  && i_showGod)    Print("🌟 GOD BUY  | Score:",fB,  " | ",Symbol()," | ",TimeToString(TimeCurrent()));
   if(godSell && i_showGod)    Print("🌟 GOD SELL | Score:",fBr, " | ",Symbol()," | ",TimeToString(TimeCurrent()));
   if(strBuy  && i_showStrong) Print("🟢 STRONG BUY  | Score:",fB);
   if(strSell && i_showStrong) Print("🔴 STRONG SELL | Score:",fBr);
   if(modBuy  && i_showMod)    Print("🟡 MOD BUY  | Score:",fB);
   if(modSell && i_showMod)    Print("🟠 MOD SELL | Score:",fBr);

   if(godBuy  || strBuy  || (i_tradeOnMod && modBuy))  PlaceTrade(true);
   if(godSell || strSell || (i_tradeOnMod && modSell)) PlaceTrade(false);
}
//+------------------------------------------------------------------+

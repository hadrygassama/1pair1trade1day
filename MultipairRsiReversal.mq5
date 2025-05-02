//+------------------------------------------------------------------+
//|                                                           MultipairRsiReversal.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Trade\SymbolInfo.mqh>

// Trading direction enum
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

// RSI strategy type enum
enum ENUM_RSI_STRATEGY {
   RSI_REVERSAL,        // REVERSAL - Buy (RSI<30), sell (RSI>70)
   RSI_CONTINUATION     // Buy (RSI>70), sell (RSI<30)
};

// Expert parameters
input group    "=== Trading Settings ==="
input string Pairs = "EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,USDCAD,USDCHF,AUDJPY,NZDJPY,CADJPY,CHFJPY,EURAUD,EURNZD,EURCAD,EURCHF,GBPAUD,GBPCAD,GBPCHF,AUDCAD,AUDCHF,CADCHF,EURCHF,GBPCHF,NZDCHF,NZDCAD";  // Pairs to trade
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input double   Lots = 0.1;            // Lots
input int      Magic = 548762;         // Magic
input int      MaxSpread = 40;         // Max spread (pips)
input int      MaxTradesPerPair = 0;   // Max trades per pair (0 = unlimited)
input int      MaxTotalTrades = 0;     // Max trades for all pairs (0 = unlimited)
input int      MaxTradesPerPairPerDay = 0;  // Max trades per pair per day (0 = unlimited)
input int      MaxTradesPerDay = 0;         // Max trades per day for all pairs (0 = unlimited)

input group    "=== Time Settings ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input bool     AutoDetectBrokerOffset = true;  // Auto-detect broker time offset
input bool     BrokerIsAheadOfGMT = false;     // Broker time is ahead of GMT (e.g. GMT+2)
input int      ManualBrokerOffset = 3;         // Manual broker GMT offset in hours

input group    "=== RSI Filter ==="
input ENUM_RSI_STRATEGY RsiStrategy = RSI_REVERSAL;  // RSI strategy type
input ENUM_TIMEFRAMES RsiTimeframe = PERIOD_CURRENT;  // RSI timeframe
input int      RsiPeriod = 14;         // Period
input int      RsiBuyLevel = 30;       // RSI Buy level
input int      RsiSellLevel = 70;      // RSI ell level

input group    "=== Exit Conditions ==="
input int      TakeProfitPoints = 30;  // Take Profit
input int      TrailingStopPoints = 20;  // Trailing Stop
input int      TrailingStartPoints = 10;  // Trailing Start

input group    "=== DCA Settings ==="
input int      MaxDCAPositions = 0;    // Max DCA positions (0 = unlimited)
input bool     EnableLotMultiplier = true;  // Enable lot multiplier for DCA
input double   LotMultiplier = 1.5;      // DCA lot multiplier
input double   MaxLotEntry = 1;        // Maximum lot size for DCA entries

input group    "=== Interface Settings ==="
input bool     Info = true;            // Show panel
input ENUM_BASE_CORNER PanelCorner = CORNER_LEFT_UPPER;  // Corner
input int      PanelXDistance = 20;    // X distance
input int      PanelYDistance = 20;    // Y distance
input int      FontSize = 12;          // Font size
input color    TextColor = clrWhite;   // Text color

input group    "=== Debug Settings ==="
input bool     Debug = false;          // Show debug logs
input int      InfoPanelRefreshSec = 5; // Info panel refresh (sec)

// Global variables
CTrade trade;
string expertName = "1pair1trade1day";
double lastBidPriceArray[100];      // 100 paires max
datetime lastOpenTimeArray[100];    // 100 paires max
double initialBalance = 0;
double maxBuyDD = 0;
double maxSellDD = 0;
double maxTotalDD = 0;
string pairsArray[];  // Array to store currency pairs
string accountCurrency = "";      // Currency of the trading account
MqlDateTime timeStruct;
datetime currentTime;
double currentSpread;
double spreadInPips;
bool canOpenBuy;
bool canOpenSell;
double currentBid;
double currentAsk;
double point;
int totalBuyPositions;
int totalSellPositions;
double buyTotalProfit = 0;
double sellTotalProfit = 0;
double totalProfit = 0;
double buyAvgPrice = 0;
double sellAvgPrice = 0;
double buyLots = 0;
double sellLots = 0;
double currentBuyDD = 0;
double currentSellDD = 0;
double currentTotalDD = 0;
const int PanelWidth = 1200;  // Panel width constant

// Structure to store position information
struct PositionInfo {
   double avgPrice;
   double totalProfit;
   double totalLots;
   int count;
   double currentDD;
   double maxDD;
   double closedProfit;
   double initialBalance;  // Ajout du solde initial par paire
   double maxProfit;      // Ajout du profit maximum par paire
};

// Tableaux pour le suivi par paire
PositionInfo buyInfoArray[100];
PositionInfo sellInfoArray[100];
double totalClosedProfit = 0;  // Profit total des trades fermés pour le compte

// Variables pour cache RSI par symbole
struct RsiCache {
   datetime lastBarTime;
   double lastRsi;
};
RsiCache rsiCache[100]; // 100 paires max

datetime lastPanelUpdate = 0;
datetime lastStatsUpdate = 0;
datetime lastBarTimeGlobal = 0;
int dailyTradesPerPair[100];        // Trades count per pair for current day
int totalDailyTrades = 0;           // Total trades for current day
datetime lastDayReset = 0;          // Last day reset time

//+------------------------------------------------------------------+
//| Detect broker time offset automatically                           |
//+------------------------------------------------------------------+
int DetectBrokerOffset() {
   datetime localTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   
   // Calculate difference in hours
   int diffSeconds = (int)(localTime - gmtTime);
   int diffHours = diffSeconds / 3600;
   
   // Round to nearest hour
   if(MathAbs(diffSeconds % 3600) > 1800) {
      diffHours += (diffSeconds > 0 ? 1 : -1);
   }
   
   return diffHours;
}

//+------------------------------------------------------------------+
//| Convert local time to broker time                                    |
//+------------------------------------------------------------------+
datetime LocalToBrokerTime(datetime localTime) {
   datetime gmtTime = TimeGMT();
   int brokerOffset = AutoDetectBrokerOffset ? DetectBrokerOffset() : (BrokerIsAheadOfGMT ? ManualBrokerOffset : -ManualBrokerOffset);
   return gmtTime + brokerOffset * 3600;  // Conversion en secondes
}

//+------------------------------------------------------------------+
//| Get RSI value using MT5's built-in indicator                      |
//+------------------------------------------------------------------+
double GetRSI(string symbol, int period, ENUM_APPLIED_PRICE price) {
   // Check if symbol is available
   if(!SymbolSelect(symbol, true)) {
      return -1;
   }
   
   // Check if symbol is active
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL) {
      return -1;
   }
   
   // Get RSI indicator handle
   int rsiHandle = iRSI(symbol, RsiTimeframe, period, price);
   if(rsiHandle == INVALID_HANDLE) {
      return -1;
   }
   
   int maxWait = 5000; // Maximum 5 seconds
   int waited = 0;
   while(BarsCalculated(rsiHandle) < period + 1) {
      Sleep(100);
      waited += 100;
      if(waited >= maxWait) {
         IndicatorRelease(rsiHandle);
         return -1;
      }
   }
   
   // Copy RSI value with multiple attempts
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   int maxTries = 3;
   int tries = 0;
   int copied = 0;
   
   while(tries < maxTries) {
      copied = CopyBuffer(rsiHandle, 0, 0, period + 1, rsiBuffer);
      if(copied == period + 1) break;
      
      tries++;
      if(tries < maxTries) {
         Sleep(100);
      }
   }
   
   if(copied != period + 1) {
      IndicatorRelease(rsiHandle);
      return -1;
   }
   
   // Check if value is valid
   if(rsiBuffer[0] == 0 || rsiBuffer[0] == EMPTY_VALUE) {
      return -1;
   }
   
   // Release handle and return value
   double rsiValue = rsiBuffer[0];
   IndicatorRelease(rsiHandle);
   return rsiValue;
}

//+------------------------------------------------------------------+
//| Convert pair name to broker format                                |
//+------------------------------------------------------------------+
string NormalizePairName(string basicPair) {
   string base = "";
   string quote = "";
   
   // Clean pair from special characters and extract currencies
   string cleanPair = basicPair;
   StringReplace(cleanPair, "/", "");
   StringReplace(cleanPair, "-", "");
   StringReplace(cleanPair, "_", "");
   StringReplace(cleanPair, "|", "");
   StringReplace(cleanPair, ".", "");
   
   // Find currency codes (3 uppercase letters)
   int basePos = -1;
   int quotePos = -1;
   
   for(int i = 0; i < StringLen(cleanPair) - 2; i++) {
      string segment = StringSubstr(cleanPair, i, 3);
      // Check if all 3 characters are uppercase letters (A-Z)
      bool isUpperCase = true;
      for(int j = 0; j < 3; j++) {
         ushort ch = StringGetCharacter(segment, j);
         if(ch < 65 || ch > 90) { // ASCII: A=65, Z=90
            isUpperCase = false;
            break;
         }
      }
      
      if(isUpperCase) {
         if(basePos == -1) {
            basePos = i;
            base = segment;
         } else if(quotePos == -1) {
            quotePos = i;
            quote = segment;
            break;
         }
      }
   }
   
   if(basePos == -1 || quotePos == -1) {
      return basicPair;
   }
   
   // Search for pair in broker's symbol list
   string brokerFormat = "";
   
   // Get complete symbol list
   for(int i = 0; i < SymbolsTotal(true); i++) {
      string symbol = SymbolName(i, true);
      
      // Clean symbol for comparison
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if symbol contains both currencies in correct order
      if(StringFind(cleanSymbol, base) >= 0 && StringFind(cleanSymbol, quote) >= 0) {
         // Check if order is correct (base before quote)
         int symbolBasePos = StringFind(cleanSymbol, base);
         int symbolQuotePos = StringFind(cleanSymbol, quote);
         if(symbolBasePos < symbolQuotePos) {
            brokerFormat = symbol;
            break;
         }
      }
   }
   
   if(brokerFormat == "") {
      return basicPair;
   }
   
   return brokerFormat;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit() {
   // Validate trading parameters
   if(Lots <= 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeStartHour < 0 || TimeStartHour > 23) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeEndHour < 0 || TimeEndHour > 23) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeStartHour >= TimeEndHour) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxSpread <= 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate RSI parameters
   if(RsiPeriod <= 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(RsiBuyLevel < 0 || RsiBuyLevel > 100) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(RsiSellLevel < 0 || RsiSellLevel > 100) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate stop loss/take profit parameters
   if(TrailingStopPoints < 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TrailingStartPoints < 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate interface parameters
   if(FontSize <= 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate pairs string
   if(StringLen(Pairs) == 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize pairs array
   StringSplit(Pairs, ',', pairsArray);
   if(ArraySize(pairsArray) == 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate each pair
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string normalizedPair = NormalizePairName(pairsArray[i]);
      if(!SymbolSelect(normalizedPair, true)) {
         return INIT_PARAMETERS_INCORRECT;
      }
      // Update array with normalized name
      pairsArray[i] = normalizedPair;
   }
   
   // Validate DCA parameters
   if(MaxDCAPositions < 0) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(Magic);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxBuyDD = 0;
   maxSellDD = 0;
   maxTotalDD = 0;
   
   // Get account currency
   accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   if(accountCurrency == "") accountCurrency = "USD";  // Default to USD if not available
   
   // Set chart colors to black
   // ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);     // Set background color to black
   // ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);     // Set text and scale color to black
   // ChartSetInteger(0, CHART_COLOR_GRID, clrBlack);          // Set grid color to black
   // ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);      // Set bullish candle color to black
   // ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);    // Set bearish candle color to black
   // ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);    // Set chart line color to black
   // ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrBlack);   // Set bullish candle body color to black
   // ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);   // Set bearish candle body color to black
   // ChartSetInteger(0, CHART_COLOR_BID, clrBlack);           // Set bid line color to black
   // ChartSetInteger(0, CHART_COLOR_ASK, clrBlack);           // Set ask line color to black
   // ChartSetInteger(0, CHART_COLOR_LAST, clrBlack);          // Set last price line color to black
   // ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlack);    // Set stop levels color to black
   // ChartSetInteger(0, CHART_SHOW_GRID, false);              // Hide grid
   // ChartSetInteger(0, CHART_SHOW_VOLUMES, false);           // Hide volumes
   // ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, false);        // Hide period separators
   // ChartSetInteger(0, CHART_SHOW_OHLC, false);              // Hide OHLC values
   // ChartSetInteger(0, CHART_SHOW_ASK_LINE, false);          // Hide ask line
   // ChartSetInteger(0, CHART_SHOW_BID_LINE, false);          // Hide bid line
   // ChartSetInteger(0, CHART_SHOW_LAST_LINE, false);         // Hide last price line
   // ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);      // Hide object descriptions
   // ChartSetInteger(0, CHART_COLOR_VOLUME, clrBlack);        // Set volume color to black
   // ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlack);    // Set stop levels color to black
   // ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlack);    // Set take profit levels color to black
   // ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlack);    // Set modification levels color to black
   
   // Désactiver le défilement automatique et le décalage
   // ChartSetInteger(0, CHART_AUTOSCROLL, false);             // Désactiver le défilement automatique
   // ChartSetInteger(0, CHART_SHIFT, false);                  // Désactiver le décalage
   
   // Masquer l'historique de trading
   // ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);     // Cacher l'historique de trading
   // ChartSetInteger(0, CHART_SHOW_TRADE_LEVELS, false);      // Cacher les niveaux de trading
   // ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);      // Cacher les descriptions des objets
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Delete EA objects
   ObjectsDeleteAll(0, "EA_Info_");
   
   // Restore default chart colors
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);
   ChartSetInteger(0, CHART_COLOR_GRID, clrLightGray);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack);
   ChartSetInteger(0, CHART_COLOR_BID, clrLightSlateGray);
   ChartSetInteger(0, CHART_COLOR_ASK, clrLightSlateGray);
   ChartSetInteger(0, CHART_COLOR_LAST, clrLightSlateGray);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrRed);
   ChartSetInteger(0, CHART_SHOW_GRID, true);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, true);
   ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(0, CHART_SHOW_OHLC, true);
   ChartSetInteger(0, CHART_SHOW_ASK_LINE, true);
   ChartSetInteger(0, CHART_SHOW_BID_LINE, true);
   ChartSetInteger(0, CHART_SHOW_LAST_LINE, true);
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true);
   ChartSetInteger(0, CHART_COLOR_VOLUME, clrGreen);
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrRed);      // Restaurer la couleur des stops
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrLime);     // Restaurer la couleur des take profits
   ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, clrBlue);     // Restaurer la couleur des modifications
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Get current time using GMT
   currentTime = TimeGMT();
   TimeToStruct(currentTime, timeStruct);
   
   // Rafraîchir le panneau d'info toutes les InfoPanelRefreshSec secondes
   if(Info && (TimeCurrent() - lastPanelUpdate > InfoPanelRefreshSec)) {
      UpdateInfoPanel();
      lastPanelUpdate = TimeCurrent();
   }
   
   // Rafraîchir les stats globales à chaque nouvelle barre
   datetime currentBarTimeGlobal = iTime(pairsArray[0], PERIOD_CURRENT, 0);
   if(currentBarTimeGlobal != lastBarTimeGlobal) {
      UpdatePositionStatistics();
      lastBarTimeGlobal = currentBarTimeGlobal;
   }
   
   // Check trading hours (using broker time)
   int currentHour = timeStruct.hour;
   int currentMinute = timeStruct.min;
   int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
   int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
   int currentTimeInMinutes = currentHour * 60 + currentMinute;
   if(startTimeInMinutes <= endTimeInMinutes) {
      if(currentTimeInMinutes < startTimeInMinutes || currentTimeInMinutes >= endTimeInMinutes) return;
   } else {
      if(currentTimeInMinutes < startTimeInMinutes && currentTimeInMinutes >= endTimeInMinutes) return;
   }
   
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string currentSymbol = pairsArray[i];
      point = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
      double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
      currentSpread = ask - bid;
      spreadInPips = currentSpread / (point * 10);
      if(spreadInPips > MaxSpread) continue;
      
      canOpenBuy = false;
      canOpenSell = false;
      
      // RSI cache par symbole - calculé une seule fois par bougie
      datetime barTime = iTime(currentSymbol, PERIOD_CURRENT, 0);
      if(rsiCache[i].lastBarTime != barTime) {
         rsiCache[i].lastRsi = GetRSI(currentSymbol, RsiPeriod, PRICE_CLOSE);
         rsiCache[i].lastBarTime = barTime;
      }
      
      // Check buy conditions
      if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
         bool rsiCondition = (RsiStrategy == RSI_REVERSAL) ? (rsiCache[i].lastRsi < RsiBuyLevel) : (rsiCache[i].lastRsi > RsiSellLevel);
         if(rsiCondition) {
            canOpenBuy = true;
         }
         if(Debug) {
            Print(StringFormat("[%s] Buy check - Symbol: %s RSI: %f RSI Condition: %s",
               TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               currentSymbol, rsiCache[i].lastRsi, rsiCondition ? "true" : "false"));
         }
      }
      
      // Check sell conditions
      if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
         bool rsiCondition = (RsiStrategy == RSI_REVERSAL) ? (rsiCache[i].lastRsi > RsiSellLevel) : (rsiCache[i].lastRsi < RsiBuyLevel);
         if(rsiCondition) {
            canOpenSell = true;
         }
         if(Debug) {
            Print(StringFormat("[%s] Sell check - Symbol: %s RSI: %f RSI Condition: %s",
               TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               currentSymbol, rsiCache[i].lastRsi, rsiCondition ? "true" : "false"));
         }
      }
      
      if(canOpenBuy || canOpenSell) {
         lastOpenTimeArray[i] = currentTime;
      }
      if(canOpenBuy) OpenBuyOrder(currentSymbol, i);
      if(canOpenSell) OpenSellOrder(currentSymbol, i);
      UpdateTrailingStops(currentSymbol, bid, ask);
      CheckDCAConditions(currentSymbol, i);
   }
}

//+------------------------------------------------------------------+
//| Reset daily trade counters                                        |
//+------------------------------------------------------------------+
void ResetDailyCounters() {
   // Use global variables instead of declaring new ones
   currentTime = TimeCurrent();
   TimeToStruct(currentTime, timeStruct);
   
   // Check if it's a new day
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDayReset, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      // Reset counters
      ArrayInitialize(dailyTradesPerPair, 0);
      totalDailyTrades = 0;
      lastDayReset = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Check if we can open a new trade                                  |
//+------------------------------------------------------------------+
bool CanOpenNewTrade(string symbol, int pairIndex) {
   // Reset daily counters if needed
   ResetDailyCounters();
   
   // Check pair limit
   if(MaxTradesPerPair > 0) {
      int currentPairTrades = CountPositions(symbol, POSITION_TYPE_BUY) + CountPositions(symbol, POSITION_TYPE_SELL);
      if(currentPairTrades >= MaxTradesPerPair) {
         if(Debug) {
            Print(StringFormat("[%s] Pair limit reached - Symbol: %s Current Trades: %d",
               TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               symbol, currentPairTrades));
         }
         return false;
      }
   }
   
   // Check total trades limit
   if(MaxTotalTrades > 0) {
      int totalTrades = 0;
      for(int i = 0; i < ArraySize(pairsArray); i++) {
         totalTrades += CountPositions(pairsArray[i], POSITION_TYPE_BUY) + CountPositions(pairsArray[i], POSITION_TYPE_SELL);
      }
      if(totalTrades >= MaxTotalTrades) {
         if(Debug) {
            Print(StringFormat("[%s] Total trades limit reached - Total Trades: %d",
               TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
               totalTrades));
         }
         return false;
      }
   }
   
   // Check pair daily limit
   if(MaxTradesPerPairPerDay > 0 && dailyTradesPerPair[pairIndex] >= MaxTradesPerPairPerDay) {
      if(Debug) {
         Print(StringFormat("[%s] Pair daily limit reached - Symbol: %s Daily Trades: %d",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
            symbol, dailyTradesPerPair[pairIndex]));
      }
      return false;
   }
   
   // Check total daily limit
   if(MaxTradesPerDay > 0 && totalDailyTrades >= MaxTradesPerDay) {
      if(Debug) {
         Print(StringFormat("[%s] Total daily limit reached - Total Daily Trades: %d",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
            totalDailyTrades));
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update trade counters after opening a trade                       |
//+------------------------------------------------------------------+
void UpdateTradeCounters(int pairIndex) {
   dailyTradesPerPair[pairIndex]++;
   totalDailyTrades++;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder(string symbol, int idx) {
   if(TradeDirection == TRADE_SELL_ONLY) return;
   
   // Check daily trade limits
   if(!CanOpenNewTrade(symbol, idx)) {
      if(Debug) {
         Print(StringFormat("[%s] Trade limit reached - Symbol: %s Daily Trades: %d Total Daily Trades: %d",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
            symbol, dailyTradesPerPair[idx], totalDailyTrades));
      }
      return;
   }
   
   int buyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
   PositionInfo buyInfo = buyInfoArray[idx];
   double localRsi = rsiCache[idx].lastRsi;
   if(MaxDCAPositions == 0 || buyPositions < MaxDCAPositions) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
      if(positionsInCurrentBar == 0) {
         double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         double currentLots = Lots;
         if(EnableLotMultiplier && buyPositions > 0) {
            currentLots = Lots * MathPow(LotMultiplier, buyPositions);
            if(currentLots > MaxLotEntry) currentLots = MaxLotEntry;
         }
         currentLots = MathFloor(currentLots / volumeStep) * volumeStep;
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         currentLots = MathMax(minLot, MathMin(maxLot, currentLots));
         double profit = buyInfo.totalProfit;
         double sprd = 0.0;
         if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
         string status = "OK";
         string extra = "";
         bool rsiCondition = true;
         if(!trade.Buy(currentLots, symbol, ask, 0, 0, expertName)) {
            status = "FAIL";
            extra = IntegerToString(GetLastError());
         } else {
            // Update trade counters after successful trade
            UpdateTradeCounters(idx);
         }
         LogInfo(symbol, "BUY", localRsi, "B", currentLots, buyPositions, profit, sprd, status, extra);
      }
   } else {
      double sprd = 0.0;
      if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
      LogInfo(symbol, "BUY", localRsi, "B", Lots, buyPositions, buyInfo.totalProfit, sprd, "MAX", "dca");
   }
   buyInfoArray[idx] = buyInfo;
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder(string symbol, int idx) {
   if(TradeDirection == TRADE_BUY_ONLY) return;
   
   // Check daily trade limits
   if(!CanOpenNewTrade(symbol, idx)) {
      if(Debug) {
         Print(StringFormat("[%s] Trade limit reached - Symbol: %s Daily Trades: %d Total Daily Trades: %d",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
            symbol, dailyTradesPerPair[idx], totalDailyTrades));
      }
      return;
   }
   
   int sellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
   PositionInfo sellInfo = sellInfoArray[idx];
   double localRsi = rsiCache[idx].lastRsi;
   if(MaxDCAPositions == 0 || sellPositions < MaxDCAPositions) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
      if(positionsInCurrentBar == 0) {
         double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         double currentLots = Lots;
         if(EnableLotMultiplier && sellPositions > 0) {
            currentLots = Lots * MathPow(LotMultiplier, sellPositions);
            if(currentLots > MaxLotEntry) currentLots = MaxLotEntry;
         }
         currentLots = MathFloor(currentLots / volumeStep) * volumeStep;
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         currentLots = MathMax(minLot, MathMin(maxLot, currentLots));
         double profit = sellInfo.totalProfit;
         double sprd = 0.0;
         if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
         string status = "OK";
         string extra = "";
         bool rsiCondition = true;
         if(!trade.Sell(currentLots, symbol, bid, 0, 0, expertName)) {
            status = "FAIL";
            extra = IntegerToString(GetLastError());
         } else {
            // Update trade counters after successful trade
            UpdateTradeCounters(idx);
         }
         LogInfo(symbol, "SELL", localRsi, "S", currentLots, sellPositions, profit, sprd, status, extra);
      }
   } else {
      double sprd = 0.0;
      if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
      LogInfo(symbol, "SELL", localRsi, "S", Lots, sellPositions, sellInfo.totalProfit, sprd, "MAX", "dca");
   }
   sellInfoArray[idx] = sellInfo;
}

//+------------------------------------------------------------------+
//| Count Positions                                                    |
//+------------------------------------------------------------------+
int CountPositions(string symbol, ENUM_POSITION_TYPE positionType) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Count Positions in Current Bar                                     |
//+------------------------------------------------------------------+
int CountPositionsInCurrentBar(string symbol, ENUM_POSITION_TYPE positionType) {
   int count = 0;
   datetime currentBarTime = iTime(symbol, PERIOD_CURRENT, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType &&
            PositionGetInteger(POSITION_TIME) >= currentBarTime) {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Calculate Position Information                                     |
//+------------------------------------------------------------------+
void CalculatePositionInfo(string symbol, ENUM_POSITION_TYPE positionType, PositionInfo &info) {
   info.totalProfit = 0;
   info.currentDD = 0;
   info.closedProfit = 0;
   info.maxProfit = 0;
   
   // Si c'est la première fois qu'on calcule pour cette paire, initialiser le solde
   if(info.initialBalance == 0) {
      info.initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }
   
   double currentProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            
            currentProfit = PositionGetDouble(POSITION_PROFIT);
            info.totalProfit += currentProfit;
            
            // Mettre à jour le profit maximum
            if(info.totalProfit > info.maxProfit) {
               info.maxProfit = info.totalProfit;
            }
            
            // Calculer le drawdown actuel
            double currentDD = info.maxProfit - info.totalProfit;
            if(currentDD > info.currentDD) {
               info.currentDD = currentDD;
            }
         }
      }
   }
   
   // Mettre à jour le maxDD uniquement si le drawdown courant est supérieur
   if(info.currentDD > info.maxDD)
      info.maxDD = info.currentDD;
   
   // Calculate closed profit from history
   HistorySelect(0, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol &&
         HistoryDealGetInteger(ticket, DEAL_TYPE) == (positionType == POSITION_TYPE_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL)) {
         info.closedProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
}

//+------------------------------------------------------------------+
//| Update Position Statistics                                         |
//+------------------------------------------------------------------+
void UpdatePositionStatistics() {
   // Reset global variables
   totalProfit = 0;
   currentTotalDD = 0;
   
   // Calculate statistics for each symbol
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string symbol = pairsArray[i];
      
      // Calculate Buy positions info
      CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfoArray[i]);
      
      // Calculate Sell positions info
      CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfoArray[i]);
      
      // Update total profit
      totalProfit += buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit;
      
      // Calculer le drawdown total pour cette paire
      double pairTotalProfit = buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit;
      double pairMaxProfit = MathMax(buyInfoArray[i].maxProfit, sellInfoArray[i].maxProfit);
      double pairCurrentDD = pairMaxProfit - pairTotalProfit;
      
      // Mettre à jour le drawdown total si nécessaire
      if(pairCurrentDD > currentTotalDD) {
         currentTotalDD = pairCurrentDD;
      }
   }
   
   // Mettre à jour le maxTotalDD uniquement si le drawdown actuel est supérieur
   if(currentTotalDD > maxTotalDD) {
      maxTotalDD = currentTotalDD;
   }
}

//+------------------------------------------------------------------+
//| Update Trailing Stops                                              |
//+------------------------------------------------------------------+
// Gère les trailing stops pour les positions ouvertes
// - Pour les positions acheteuses :
//   * Ferme toutes les positions si le profit atteint le TakeProfitPoints
//   * Déplace le stop loss si le prix monte suffisamment
// - Pour les positions vendeuses :
//   * Ferme toutes les positions si le profit atteint le TakeProfitPoints
//   * Déplace le stop loss si le prix baisse suffisamment
// Paramètres :
//   symbol : Le symbole à traiter
//   bid : Prix de vente actuel
//   ask : Prix d'achat actuel
void UpdateTrailingStops(string symbol, double bid, double ask) {
   // Variables pour les positions Buy
   double localBuyTotalProfit = 0;
   double buyAveragePrice = 0;
   int buyPositionCount = 0;
   double buyTotalLots = 0;
   
   // Variables pour les positions Sell
   double localSellTotalProfit = 0;
   double sellAveragePrice = 0;
   int sellPositionCount = 0;
   double sellTotalLots = 0;
   
   // Premier passage : calcul des moyennes et profits
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               localBuyTotalProfit += positionProfit;
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               localSellTotalProfit += positionProfit;
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
            }
         }
      }
   }
   
   // Calcul des prix moyens pondérés par les lots
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stopLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * localPoint;
   
   // Gestion des profits et trailing stops pour les positions Buy
   if(buyPositionCount > 0) {
      double buyProfitInPoints = (bid - buyAveragePrice) / localPoint;
      
      // Vérifier si le Take Profit est atteint pour le groupe Buy
      if(TakeProfitPoints > 0 && buyProfitInPoints >= TakeProfitPoints) {
         ClosePositionsInDirection(symbol, POSITION_TYPE_BUY);
      }
      // Sinon, appliquer le trailing stop uniquement aux positions initiales
      else if(TrailingStopPoints != 0) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                  PositionGetString(POSITION_SYMBOL) == symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  
                  double currentSL = PositionGetDouble(POSITION_SL);
                  double newSL = 0;
                  
                  if(currentSL < buyAveragePrice || currentSL == 0) {
                     if(bid - (TrailingStopPoints + TrailingStartPoints) * localPoint >= buyAveragePrice) {
                        newSL = buyAveragePrice + TrailingStartPoints * localPoint;
                     }
                  }
                  else if(currentSL >= buyAveragePrice) {
                     if(bid - TrailingStopPoints * localPoint > currentSL) {
                        newSL = bid - TrailingStopPoints * localPoint;
                     }
                  }
                  
                  // Vérifier si le nouveau stop loss est valide
                  if(newSL > 0) {
                     // Vérifier la distance minimale par rapport au prix actuel
                     if(bid - newSL >= stopLevel) {
                        trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
            }
         }
      }
   }
   
   // Gestion des profits et trailing stops pour les positions Sell
   if(sellPositionCount > 0) {
      double sellProfitInPoints = (sellAveragePrice - ask) / localPoint;
      
      // Vérifier si le Take Profit est atteint pour le groupe Sell
      if(TakeProfitPoints > 0 && sellProfitInPoints >= TakeProfitPoints) {
         ClosePositionsInDirection(symbol, POSITION_TYPE_SELL);
      }
      // Sinon, appliquer le trailing stop uniquement aux positions initiales
      else if(TrailingStopPoints != 0) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                  PositionGetString(POSITION_SYMBOL) == symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                  
                  double currentSL = PositionGetDouble(POSITION_SL);
                  double newSL = 0;
                  
                  if(currentSL > sellAveragePrice || currentSL == 0) {
                     if(ask + (TrailingStopPoints + TrailingStartPoints) * localPoint <= sellAveragePrice) {
                        newSL = sellAveragePrice - TrailingStartPoints * localPoint;
                     }
                  }
                  else if(currentSL <= sellAveragePrice) {
                     if(ask + TrailingStopPoints * localPoint < currentSL) {
                        newSL = ask + TrailingStopPoints * localPoint;
                     }
                  }
                  
                  // Vérifier si le nouveau stop loss est valide
                  if(newSL > 0) {
                     // Vérifier la distance minimale par rapport au prix actuel
                     if(newSL - ask >= stopLevel) {
                        trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close Positions in Direction                                       |
//+------------------------------------------------------------------+
void ClosePositionsInDirection(string symbol, ENUM_POSITION_TYPE positionType) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            if(!trade.PositionClose(PositionGetTicket(i))) {
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check DCA Conditions                                              |
//+------------------------------------------------------------------+
// Vérifie les conditions pour l'ouverture de positions DCA (Dollar Cost Averaging)
// - Pour les positions acheteuses :
//   * Vérifie si le prix a baissé suffisamment par rapport au prix moyen
//   * Vérifie si le nombre maximum de positions DCA n'est pas atteint
// - Pour les positions vendeuses :
//   * Vérifie si le prix a monté suffisamment par rapport au prix moyen
//   * Vérifie si le nombre maximum de positions DCA n'est pas atteint
// Paramètres :
//   symbol : Le symbole à traiter
void CheckDCAConditions(string symbol, int idx) {
   // Variables pour Buy
   double buyAveragePrice = 0;
   double buyTotalLots = 0;
   int buyPositionCount = 0;
   
   // Variables pour Sell
   double sellAveragePrice = 0;
   double sellTotalLots = 0;
   int sellPositionCount = 0;
   
   // Calcul des moyennes pour Buy et Sell séparément
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
            }
         }
      }
   }
   
   // Calcul des prix moyens pondérés
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   // Vérifier les conditions DCA pour Buy si autorisé
   if(TradeDirection != TRADE_SELL_ONLY && buyPositionCount > 0) {
      double rsi = rsiCache[idx].lastRsi;
      bool rsiCondition = (RsiStrategy == RSI_REVERSAL) ? (rsi < RsiBuyLevel) : (rsi > RsiSellLevel);
      if(rsiCondition) {
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
         if(positionsInCurrentBar == 0) {
            OpenBuyOrder(symbol, idx);
         }
      }
   }
   
   // Vérifier les conditions DCA pour Sell si autorisé
   if(TradeDirection != TRADE_BUY_ONLY && sellPositionCount > 0) {
      double rsi = rsiCache[idx].lastRsi;
      bool rsiCondition = (RsiStrategy == RSI_REVERSAL) ? (rsi > RsiSellLevel) : (rsi < RsiBuyLevel);
      if(rsiCondition) {
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
         if(positionsInCurrentBar == 0) {
            OpenSellOrder(symbol, idx);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Label for Info Panel                                        |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) == -1) {
      CreateLabel(name, text, x, y, clr);
   } else {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, PanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, PanelCorner);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");  // Using fixed-width font for better table alignment
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);  // Make sure labels are visible
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Update Info Panel                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel() {
   if(!Info) return;
   
   string prefix = "EA_Info_";
   int x = PanelXDistance;
   int y = PanelYDistance;
   int yStep = FontSize + 4;
   
   // Calculer la largeur nécessaire pour chaque colonne
   int pairWidth = 10;  // Largeur pour la colonne "Pair"
   int rsiWidth = 6;    // Largeur pour la colonne "RSI"
   int plWidth = 11;    // Largeur pour la colonne "P/L"
   int maxddWidth = 11; // Largeur pour la colonne "MaxDD"
   int closedWidth = 11; // Largeur pour la colonne "Closed"
   
   // Calculer la largeur totale nécessaire
   int totalWidth = pairWidth + rsiWidth + plWidth + maxddWidth + closedWidth + 8; // +8 pour les séparateurs
   
   // Ajuster la largeur du panneau si nécessaire
   if(totalWidth * FontSize > PanelWidth) {
      // Réduire proportionnellement la largeur de chaque colonne
      double scaleFactor = (double)PanelWidth / (totalWidth * FontSize);
      pairWidth = (int)(pairWidth * scaleFactor);
      rsiWidth = (int)(rsiWidth * scaleFactor);
      plWidth = (int)(plWidth * scaleFactor);
      maxddWidth = (int)(maxddWidth * scaleFactor);
      closedWidth = (int)(closedWidth * scaleFactor);
   }
   
   // Table header
   string header = StringFormat("%-*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   
   // Separator line
   string tableSeparator = StringFormat("%-*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      plWidth, "--------------",
      maxddWidth, "--------------",
      closedWidth, "--------------");
   
   // Limiter à 30 paires max pour l'affichage
   int maxPairs = MathMin(ArraySize(pairsArray), 30);
   bool tooManyPairs = (ArraySize(pairsArray) > 30);

   // Tableau pour éviter les doublons
   string displayedPairs[100];
   int displayedCount = 0;

   // Informations globales du compte
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double drawdown = (balance - equity) / balance * 100;
   
   // Ligne 1: Balance et Equity
   string accountInfo1 = StringFormat("Balance: %12.2f | Equity: %12.2f", balance, equity);
   UpdateLabel(prefix + "AccountInfo1", accountInfo1, x, y, TextColor);
   y += yStep;
   
   // Ligne 2: Profit et Drawdown
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentProfit = AccountInfoDouble(ACCOUNT_PROFIT);
   double currentDrawdown = (currentBalance - currentEquity) / currentBalance * 100;
   string accountInfo2 = StringFormat("Profit: %10.2f | DD (%%): %4.2f%% |  Max DD (%s): %10.2f", 
      currentProfit, 
      currentDrawdown,
      accountCurrency,
      maxTotalDD);
   UpdateLabel(prefix + "AccountInfo2", accountInfo2, x, y, currentProfit > 0 ? clrLime : (currentProfit < 0 ? clrRed : TextColor));
   y += yStep;
   
   // Ligne 3: Nombre total de positions
   int totalPositions = PositionsTotal();
   string accountInfo3 = StringFormat("Total Positions: %d", totalPositions);
   UpdateLabel(prefix + "AccountInfo3", accountInfo3, x, y, TextColor);
   y += yStep;
   
   // Ligne séparatrice
   string separator = "------------------------------------------------------------";
   UpdateLabel(prefix + "Separator1", separator, x, y, TextColor);
   y += yStep;
   
   // Variables for totals
   double totalBuyProfit = 0;
   double totalSellProfit = 0;
   double totalBuyDD = 0;
   double totalSellDD = 0;
   double totalBuyClosed = 0;
   double totalSellClosed = 0;
   
   // ====== XXX/USD PAIRS TABLE (USD as quote) ======
   
   UpdateLabel(prefix + "UsdQuoteTitle", "XXX/USD PAIRS (USD as quote)", x, y, clrDodgerBlue);
   y += yStep;
   
   // Table header
   string headerUsdQuote = StringFormat("%-*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "UsdQuoteHeader", headerUsdQuote, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorUsdQuote = StringFormat("%-*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      plWidth, "--------------",
      maxddWidth, "--------------",
      closedWidth, "--------------");
   UpdateLabel(prefix + "UsdQuoteTableSeparator", tableSeparatorUsdQuote, x, y, TextColor);
   y += yStep;
   
   // Display information for each XXX/USD pair
   for(int i = 0; i < maxPairs; i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a XXX/USD pair
      if(StringSubstr(cleanSymbol, 3, 3) == "USD") {
         // Vérifier si déjà affichée
         bool alreadyDisplayed = false;
         for(int d = 0; d < displayedCount; d++) {
            if(displayedPairs[d] == symbol) {
               alreadyDisplayed = true;
               break;
            }
         }
         if(alreadyDisplayed) continue;
         // Ajouter à la liste des affichées
         displayedPairs[displayedCount] = symbol;
         displayedCount++;
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfoArray[i]);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfoArray[i]);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            plWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit, 2), 2),
            maxddWidth, DoubleToString(NormalizeDouble(-MathMax(buyInfoArray[i].maxDD, sellInfoArray[i].maxDD), 2), 2),
            closedWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit, 2), 2));
         
         // Determine color based on total profit
         double totalPairProfit = buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit + buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit;
         color lineColor = totalPairProfit == 0 ? TextColor : (totalPairProfit > 0 ? clrLime : clrRed);
         
         UpdateLabel(prefix + "UsdQuote_" + IntegerToString(i), line, x, y, lineColor);
         y += yStep;
         
         if(Debug) {
            Print("Pair: ", symbol, " Buy Closed: ", buyInfoArray[i].closedProfit, " Sell Closed: ", sellInfoArray[i].closedProfit);
         }
      }
   }
   
   y += yStep * 2;  // Extra space between sections
   
   // ====== USD/XXX PAIRS TABLE (USD as base) ======
   
   UpdateLabel(prefix + "UsdBaseTitle", "USD/XXX PAIRS (USD as base)", x, y, clrCrimson);
   y += yStep;
   
   // Table header
   string headerUsdBase = StringFormat("%-*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "UsdBaseHeader", headerUsdBase, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorUsdBase = StringFormat("%-*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      plWidth, "--------------",
      maxddWidth, "--------------",
      closedWidth, "--------------");
   UpdateLabel(prefix + "UsdBaseTableSeparator", tableSeparatorUsdBase, x, y, TextColor);
   y += yStep;
   
   // Display information for each USD/XXX pair
   for(int i = 0; i < maxPairs; i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a USD/XXX pair
      if(StringSubstr(cleanSymbol, 0, 3) == "USD") {
         // Vérifier si déjà affichée
         bool alreadyDisplayed = false;
         for(int d = 0; d < displayedCount; d++) {
            if(displayedPairs[d] == symbol) {
               alreadyDisplayed = true;
               break;
            }
         }
         if(alreadyDisplayed) continue;
         // Ajouter à la liste des affichées
         displayedPairs[displayedCount] = symbol;
         displayedCount++;
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfoArray[i]);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfoArray[i]);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            plWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit, 2), 2),
            maxddWidth, DoubleToString(NormalizeDouble(-MathMax(buyInfoArray[i].maxDD, sellInfoArray[i].maxDD), 2), 2),
            closedWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit, 2), 2));
         
         // Determine color based on total profit
         double totalPairProfit = buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit + buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit;
         color lineColor = totalPairProfit == 0 ? TextColor : (totalPairProfit > 0 ? clrLime : clrRed);
         
         UpdateLabel(prefix + "UsdBase_" + IntegerToString(i), line, x, y, lineColor);
         y += yStep;
      }
   }
   
   y += yStep * 2;  // Extra space between sections
   
   // ====== OTHER PAIRS TABLE (No USD) ======
   
   UpdateLabel(prefix + "OtherPairsTitle", "OTHER PAIRS (No USD)", x, y, clrGoldenrod);
   y += yStep;
   
   // Table header
   string headerOther = StringFormat("%-*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "OtherPairsHeader", headerOther, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorOther = StringFormat("%-*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      plWidth, "--------------",
      maxddWidth, "--------------",
      closedWidth, "--------------");
   UpdateLabel(prefix + "OtherPairsTableSeparator", tableSeparatorOther, x, y, TextColor);
   y += yStep;
   
   // Display information for other pairs
   for(int i = 0; i < maxPairs; i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a pair without USD
      if(StringFind(cleanSymbol, "USD") == -1) {
         // Vérifier si déjà affichée
         bool alreadyDisplayed = false;
         for(int d = 0; d < displayedCount; d++) {
            if(displayedPairs[d] == symbol) {
               alreadyDisplayed = true;
               break;
            }
         }
         if(alreadyDisplayed) continue;
         // Ajouter à la liste des affichées
         displayedPairs[displayedCount] = symbol;
         displayedCount++;
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfoArray[i]);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfoArray[i]);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            plWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit, 2), 2),
            maxddWidth, DoubleToString(NormalizeDouble(-MathMax(buyInfoArray[i].maxDD, sellInfoArray[i].maxDD), 2), 2),
            closedWidth, DoubleToString(NormalizeDouble(buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit, 2), 2));
         
         // Determine color based on total profit
         double totalPairProfit = buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit + buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit;
         color lineColor = totalPairProfit == 0 ? TextColor : (totalPairProfit > 0 ? clrLime : clrRed);
         
         UpdateLabel(prefix + "Other_" + IntegerToString(i), line, x, y, lineColor);
         y += yStep;
      }
   }
   
   // === AJOUT : Affichage du total général P/L et Closed ===
   double globalPL = 0;
   double globalClosed = 0;
   for(int i = 0; i < maxPairs; i++) {
      globalPL += buyInfoArray[i].totalProfit + sellInfoArray[i].totalProfit;
      globalClosed += buyInfoArray[i].closedProfit + sellInfoArray[i].closedProfit;
   }
   y += yStep; // espace
   string totalLine = StringFormat("TOTAL P/L: %12.2f   |   CLOSED TOTAL: %12.2f", globalPL, globalClosed);
   double globalTotal = globalPL + globalClosed;
   UpdateLabel(prefix + "GlobalTotalPL", totalLine, x, y, globalTotal > 0 ? clrLime : (globalTotal < 0 ? clrRed : TextColor));
   y += yStep;
   
   // Message d'avertissement si > 30 paires
   if(tooManyPairs) {
      UpdateLabel(prefix + "TooManyPairs", "Affichage limité aux 30 premières paires.", x, y, clrOrange);
      y += yStep;
   }
   
   // Forcer le redessinage du graphique
   ChartRedraw();
}

// Fonction de log universel
void LogInfo(string sym, string act, double rsi, string dir, double lots, int nbPos, double profit, double sprd, string status, string extra) {
   string msg = StringFormat("%s|%s|RSI:%.1f|%s|L:%.2f|N:%d|P:%.2f|S:%.1f|%s|%s",
      sym, act, rsi, dir, lots, nbPos, profit, sprd, status, extra);
   Print(msg);
} 
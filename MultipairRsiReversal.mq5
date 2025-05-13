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
   RSI_CONTINUATION     // CONTINUATION - Buy (RSI>70), sell (RSI<30)
};

// Add BB Mode enum
enum ENUM_BB_MODE {
   BB_UPPER_LOWER,  // Trade on Upper/Lower Bands
   BB_MIDDLE        // Trade on Middle Band
};

// Lot Size Settings enum
enum ENUM_LOT_CALCULATION_METHOD {
   LOT_FIXED,  // Fixed lot size
   LOT_RISK_PERCENTAGE  // Risk percentage for lot calculation
};

// Expert parameters
input group    "=== Trading Settings ==="
input string Pairs = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,USDCAD,NZDUSD,EURGBP,EURJPY,GBPJPY,EURCHF,EURAUD,GBPCHF,AUDJPY,CADJPY";  // Trading Pairs (comma separated)
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input ENUM_LOT_CALCULATION_METHOD LotCalculationMethod = LOT_FIXED;  // Lot calculation method
input double RiskPercent = 1.0;          // Risk percentage for lot calculation
input double   Lots = 0.01;            // Fixed lot size
input int      Magic = 548762;         // Magic
input int      MaxSpread = 40;         // Max spread (pips)
input int      Slippage = 3;           // Slippage in points
input int      OpenTime = 3600;        // Temps entre les ordres (secondes)

input group    "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input bool     AutoDetectBrokerOffset = true;  // Auto-detect broker time offset
input bool     BrokerIsAheadOfGMT = false;     // Broker time is ahead of GMT (e.g. GMT+2)
input int      ManualBrokerOffset = 3;         // Manual broker GMT offset in hours

input group    "=== Trade Limits ==="
input int      MaxDailyBuyTradesPerPair = 0;    // Max daily buy trades per pair (0 = unlimited)
input int      MaxDailySellTradesPerPair = 0;   // Max daily sell trades per pair (0 = unlimited)
input int      MaxDailyTradesOnAccount = 0;      // Max daily trades on the account (0 = unlimited)
input int      MaxBuyTradesPerPair = 0;         // Max buy trades per pair (0 = unlimited)
input int      MaxSellTradesPerPair = 0;        // Max sell trades per pair (0 = unlimited)
input int      MaxTradesOnAccount = 0;          // Max trades on the account (0 = unlimited)

input group    "=== RSI Strategy ==="
input bool     UseRsiFilter = true;         // Enable RSI Filter
input ENUM_RSI_STRATEGY RsiStrategy = RSI_REVERSAL;  // RSI strategy type
input ENUM_TIMEFRAMES RsiTimeframe = PERIOD_CURRENT;  // RSI timeframe
input int      RsiPeriod = 14;         // Period
input int      RsiBuyLevel = 30;       // RSI Buy level
input int      RsiSellLevel = 70;      // RSI Sell level

input group    "=== ADX Filter ==="
input bool     UseAdxFilter = false;    // Enable ADX Filter
input ENUM_TIMEFRAMES AdxTimeframe = PERIOD_CURRENT;  // ADX timeframe
input int      AdxPeriod = 14;         // ADX Period
input double   AdxMinThreshold = 50;      // Minimum ADX Threshold
input double   AdxMaxThreshold = 100;      // Maximum ADX Threshold

input group    "=== Moving Average Filter ==="
input bool     UseMaFilter = false;     // Enable MA Filter
input ENUM_TIMEFRAMES MaTimeframe = PERIOD_CURRENT;  // MA timeframe
input int      MaPeriod = 20;          // MA Period
input ENUM_MA_METHOD MaMethod = MODE_EMA;  // MA Method (SMA/EMA)
input bool     BuyAboveMa = false;      // Buy when price above MA
input bool     SellBelowMa = false;     // Sell when price below MA
input int      EmaRangePoints = 0;  // Range around EMA (points, 0 = disabled)

input group    "=== Bollinger Bands Filter ==="
input bool     UseBBFilter = true;     // Enable Bollinger Bands Filter
input ENUM_TIMEFRAMES BBTimeframe = PERIOD_CURRENT;  // BB timeframe
input int      BBPeriod = 20;          // BB Period
input double   BBDeviation = 2.0;      // BB Deviation
input ENUM_BB_MODE BBMode = BB_UPPER_LOWER; // BB Trading Mode
input bool     BuyAboveBB = false;      // Buy when price above BB
input bool     SellBelowBB = false;     // Sell when price below BB

// Add BB cache structure
struct BBCache {
   datetime lastBarTime;
   double upperBand;
   double middleBand;
   double lowerBand;
   bool initialized;
};

// Add BB cache array
BBCache bbCache[100];   // 100 paires max

input group    "=== Exit Conditions ==="
input int      TakeProfitPoints = 30;  // Take Profit (points)
input int      TrailingStopPoints = 20;  // Trailing Stop (points)
input int      TrailingStartPoints = 10;  // Trailing Start (points)
input int      StopLossPoints = 0;  // Stop loss (points, 0 = disabled)

input group    "=== DCA Settings ==="
input bool     EnableDCA = true;  // Enable DCA settings
input int      MaxDCAPositions = 0;    // Max DCA positions (0 = unlimited)
input bool     EnableLotMultiplier = false;  // Enable lot multiplier for DCA
input double   LotMultiplier = 1.5;      // Lot multiplier for DCA
input double   MaxLotEntry = 1.0;        // Maximum lot size for entries

input group    "=== Risk Management ==="
input bool     EnableMaxDrawdown = true;    // Enable max drawdown protection
input double   MaxDrawdownPercent = 30.0;    // Max drawdown before stopping new trades (%, 0 = disabled)
input bool     CloseAllOnEmergency = false;  // Close all trades on emergency drawdown
input double   EmergencyDrawdownPercent = 0;  // Emergency drawdown to close all trades (%, 0 = disabled)
input double   MaxDailyProfitPercent = 0;  // Max daily profit before stopping new trades (0 = disabled)
input double   ProfitTargetAmount = 1000.0;  // Profit target amount in USD to close all positions

input group    "=== Interface Settings ==="
input bool     Info = true;            // Show panel
input ENUM_BASE_CORNER PanelCorner = CORNER_LEFT_UPPER;  // Corner
input int      PanelXDistance = 20;    // X distance
input int      PanelYDistance = 20;    // Y distance
input int      FontSize = 10;          // Font size (réduit pour petit écran)
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
double totalProfit = 0;  // Added totalProfit declaration
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
double globalTotalProfit = 0;  // Renamed from totalProfit to avoid hiding
double buyAvgPrice = 0;
double sellAvgPrice = 0;
double buyLots = 0;
double sellLots = 0;
double currentBuyDD = 0;
double currentSellDD = 0;
double currentTotalDD = 0;
const int PanelWidth = 1200;  // Panel width constant

datetime lastProfitReset = 0; // Ajout pour le reset du profit target

// Variables for daily trade tracking
datetime lastDayReset = 0;    // Last time daily counters were reset

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

// Structure pour le cache ADX
struct AdxCache {
   datetime lastBarTime;
   double lastAdx;
   double lastPlusDI;
   double lastMinusDI;
   bool initialized;  // Add initialization flag
};

// Structure pour le cache MA
struct MaCache {
   datetime lastBarTime;
   double lastMa;
   bool initialized;  // Add initialization flag
};

// Variables pour cache RSI par symbole
struct RsiCache {
   datetime lastBarTime;
   double lastRsi;
};
RsiCache rsiCache[100]; // 100 paires max
AdxCache adxCache[100]; // 100 paires max
MaCache maCache[100];   // 100 paires max

datetime lastPanelUpdate = 0;
datetime lastStatsUpdate = 0;
datetime lastBarTimeGlobal = 0;

// Add global variables to track daily trades
int dailyBuyTrades[100];
int dailySellTrades[100];

// Add after the global variables section
double dailyProfit = 0;  // Track daily profit
double dailyProfitPercent = 0;  // Track daily profit percentage
double dailyInitialBalance = 0;  // Track initial balance for the day

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
//| Get ADX value using MT5's built-in indicator                      |
//+------------------------------------------------------------------+
double GetADX(string symbol, int period) {
   // Check if symbol is available
   if(!SymbolSelect(symbol, true)) {
      return -1;
   }
   
   // Get ADX indicator handle
   int adxHandle = iADX(symbol, AdxTimeframe, period);
   if(adxHandle == INVALID_HANDLE) {
      return -1;
   }
   
   int maxWait = 5000; // Maximum 5 seconds
   int waited = 0;
   while(BarsCalculated(adxHandle) < period + 1) {
      Sleep(100);
      waited += 100;
      if(waited >= maxWait) {
         IndicatorRelease(adxHandle);
         return -1;
      }
   }
   
   // Copy ADX values
   double adxBuffer[];
   double plusDIBuffer[];
   double minusDIBuffer[];
   
   ArraySetAsSeries(adxBuffer, true);
   ArraySetAsSeries(plusDIBuffer, true);
   ArraySetAsSeries(minusDIBuffer, true);
   
   int copied = CopyBuffer(adxHandle, 0, 0, period + 1, adxBuffer);
   int copiedPlus = CopyBuffer(adxHandle, 1, 0, period + 1, plusDIBuffer);
   int copiedMinus = CopyBuffer(adxHandle, 2, 0, period + 1, minusDIBuffer);
   
   if(copied != period + 1 || copiedPlus != period + 1 || copiedMinus != period + 1) {
      IndicatorRelease(adxHandle);
      return -1;
   }
   
   // Check if values are valid
   if(adxBuffer[0] == 0 || adxBuffer[0] == EMPTY_VALUE ||
      plusDIBuffer[0] == 0 || plusDIBuffer[0] == EMPTY_VALUE ||
      minusDIBuffer[0] == 0 || minusDIBuffer[0] == EMPTY_VALUE) {
      IndicatorRelease(adxHandle);
      return -1;
   }
   
   // Store values in cache
   int idx = GetPairIndex(symbol);
   if(idx >= 0) {
      adxCache[idx].lastAdx = adxBuffer[0];
      adxCache[idx].lastPlusDI = plusDIBuffer[0];
      adxCache[idx].lastMinusDI = minusDIBuffer[0];
      adxCache[idx].lastBarTime = iTime(symbol, PERIOD_CURRENT, 0);
      adxCache[idx].initialized = true;
   }
   
   IndicatorRelease(adxHandle);
   return adxBuffer[0];
}

//+------------------------------------------------------------------+
//| Get pair index from pairs array                                   |
//+------------------------------------------------------------------+
int GetPairIndex(string symbol) {
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      if(pairsArray[i] == symbol) {
         return i;
      }
   }
   return -1;
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
   
   // Validate drawdown parameters
   if(EnableMaxDrawdown) {
      if(MaxDrawdownPercent <= 0) {
         Print("Error: MaxDrawdownPercent must be greater than 0 when EnableMaxDrawdown is true");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(CloseAllOnEmergency && EmergencyDrawdownPercent <= 0) {
         Print("Error: EmergencyDrawdownPercent must be greater than 0 when CloseAllOnEmergency is true");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(CloseAllOnEmergency && EmergencyDrawdownPercent >= MaxDrawdownPercent) {
         Print("Error: EmergencyDrawdownPercent must be less than MaxDrawdownPercent");
         return INIT_PARAMETERS_INCORRECT;
      }
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
   // Check profit target first
   if(CheckProfitTarget()) {
      return;
   }
   
   // Get current time using GMT
   currentTime = TimeGMT();
   TimeToStruct(currentTime, timeStruct);
   
   // Update daily profit
   UpdateDailyProfit();
   
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
   
   // Reset daily trade counters if it's a new day
   ResetDailyCounters();
   
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
      
      // RSI, ADX, MA and BB cache par symbole - calculé une seule fois par bougie
      datetime barTime = iTime(currentSymbol, PERIOD_CURRENT, 0);
      if(rsiCache[i].lastBarTime != barTime) {
         rsiCache[i].lastRsi = GetRSI(currentSymbol, RsiPeriod, PRICE_CLOSE);
         rsiCache[i].lastBarTime = barTime;
      }
      if(UseAdxFilter && (adxCache[i].lastBarTime != barTime || !adxCache[i].initialized)) {
         adxCache[i].lastAdx = GetADX(currentSymbol, AdxPeriod);
         adxCache[i].lastBarTime = barTime;
      }
      if(UseMaFilter && (maCache[i].lastBarTime != barTime || !maCache[i].initialized)) {
         maCache[i].lastMa = GetMA(currentSymbol, MaPeriod, MaMethod);
         maCache[i].lastBarTime = barTime;
      }
      if(UseBBFilter && (bbCache[i].lastBarTime != barTime || !bbCache[i].initialized)) {
         GetBB(currentSymbol, BBPeriod, BBDeviation, BBMode);
         bbCache[i].lastBarTime = barTime;
      }
      
      if(Debug) {
         Print(StringFormat("[%s] Indicators - RSI: %s ADX: %s MA: %s BB: %s Bid: %f Ask: %f Spread: %f",
            currentSymbol,
            UseRsiFilter ? DoubleToString(rsiCache[i].lastRsi, 2) : "N/A",
            UseAdxFilter ? DoubleToString(adxCache[i].lastAdx, 2) : "N/A",
            UseMaFilter ? DoubleToString(maCache[i].lastMa, 2) : "N/A",
            UseBBFilter ? DoubleToString(bbCache[i].middleBand, 2) : "N/A",
            bid,
            ask,
            spreadInPips));
      }
      
      // Check buy conditions
      if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
         bool rsiCondition = !UseRsiFilter || ((RsiStrategy == RSI_REVERSAL) ? (rsiCache[i].lastRsi < RsiBuyLevel) : (rsiCache[i].lastRsi > RsiBuyLevel));
         bool adxCondition = !UseAdxFilter || (adxCache[i].lastAdx > AdxMinThreshold && adxCache[i].lastAdx < AdxMaxThreshold);
         bool maCondition = !UseMaFilter || (BuyAboveMa ? (bid > maCache[i].lastMa) : (bid < maCache[i].lastMa));
         bool emaRangeCondition = (EmaRangePoints == 0) || (bid < maCache[i].lastMa - EmaRangePoints * point || bid > maCache[i].lastMa + EmaRangePoints * point);
         bool bbCondition = !UseBBFilter || (
            BBMode == BB_UPPER_LOWER ? 
               (BuyAboveBB ? (bid > bbCache[i].upperBand) : (bid < bbCache[i].lowerBand)) :
               (BuyAboveBB ? (bid > bbCache[i].middleBand) : (bid < bbCache[i].middleBand))
         );
         
         if(rsiCondition && adxCondition && maCondition && emaRangeCondition && bbCondition) {
            canOpenBuy = true;
         }
         
         if(Debug) {
            Print(StringFormat("[%s] Buy check - RSI Condition: %s (%s %s %d) ADX Condition: %s (%s %s %f) MA Condition: %s (%f %s %s) BB Condition: %s (%f %s %s)",
               currentSymbol,
               rsiCondition ? "true" : "false",
               UseRsiFilter ? DoubleToString(rsiCache[i].lastRsi, 2) : "N/A",
               (RsiStrategy == RSI_REVERSAL) ? "<" : ">",
               (RsiStrategy == RSI_REVERSAL) ? RsiBuyLevel : RsiBuyLevel,
               adxCondition ? "true" : "false",
               UseAdxFilter ? DoubleToString(adxCache[i].lastAdx, 2) : "N/A",
               ">",
               AdxMinThreshold,
               maCondition ? "true" : "false",
               bid,
               BuyAboveMa ? ">" : "<",
               UseMaFilter ? DoubleToString(maCache[i].lastMa, 2) : "N/A",
               bbCondition ? "true" : "false",
               bid,
               BuyAboveBB ? ">" : "<",
               UseBBFilter ? DoubleToString(bbCache[i].middleBand, 2) : "N/A"));
         }
      }
      
      // Check sell conditions
      if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
         bool rsiCondition = !UseRsiFilter || ((RsiStrategy == RSI_REVERSAL) ? (rsiCache[i].lastRsi > RsiSellLevel) : (rsiCache[i].lastRsi < RsiSellLevel));
         bool adxCondition = !UseAdxFilter || (adxCache[i].lastAdx > AdxMinThreshold && adxCache[i].lastAdx < AdxMaxThreshold);
         bool maCondition = !UseMaFilter || (SellBelowMa ? (ask < maCache[i].lastMa) : (ask > maCache[i].lastMa));
         bool emaRangeCondition = (EmaRangePoints == 0) || (ask < maCache[i].lastMa - EmaRangePoints * point || ask > maCache[i].lastMa + EmaRangePoints * point);
         bool bbCondition = !UseBBFilter || (
            BBMode == BB_UPPER_LOWER ? 
               (SellBelowBB ? (ask < bbCache[i].lowerBand) : (ask > bbCache[i].upperBand)) :
               (SellBelowBB ? (ask < bbCache[i].middleBand) : (ask > bbCache[i].middleBand))
         );
         
         if(rsiCondition && adxCondition && maCondition && emaRangeCondition && bbCondition) {
            canOpenSell = true;
         }
         
         if(Debug) {
            Print(StringFormat("[%s] Sell check - RSI Condition: %s (%s %s %d) ADX Condition: %s (%s %s %f) MA Condition: %s (%f %s %s) BB Condition: %s (%f %s %s)",
               currentSymbol,
               rsiCondition ? "true" : "false",
               UseRsiFilter ? DoubleToString(rsiCache[i].lastRsi, 2) : "N/A",
               (RsiStrategy == RSI_REVERSAL) ? ">" : "<",
               (RsiStrategy == RSI_REVERSAL) ? RsiSellLevel : RsiSellLevel,
               adxCondition ? "true" : "false",
               UseAdxFilter ? DoubleToString(adxCache[i].lastAdx, 2) : "N/A",
               ">",
               AdxMinThreshold,
               maCondition ? "true" : "false",
               ask,
               SellBelowMa ? "<" : ">",
               UseMaFilter ? DoubleToString(maCache[i].lastMa, 2) : "N/A",
               bbCondition ? "true" : "false",
               ask,
               SellBelowBB ? "<" : ">",
               UseBBFilter ? DoubleToString(bbCache[i].middleBand, 2) : "N/A"));
         }
      }
      
      if(canOpenBuy || canOpenSell) {
         // Suppression de la mise à jour prématurée de lastOpenTimeArray
      }
      
      // Vérification des conditions pour l'ouverture d'un ordre d'achat
      if(canOpenBuy && 
         (MaxDailyBuyTradesPerPair == 0 || dailyBuyTrades[i] < MaxDailyBuyTradesPerPair) &&
         (MaxBuyTradesPerPair == 0 || CountPositions(pairsArray[i], POSITION_TYPE_BUY) < MaxBuyTradesPerPair) &&
         (MaxTradesOnAccount == 0 || PositionsTotal() < MaxTradesOnAccount) &&
         (MaxDailyTradesOnAccount == 0 || (dailyBuyTrades[i] + dailySellTrades[i]) < MaxDailyTradesOnAccount) &&
         (currentTime - lastOpenTimeArray[i] >= OpenTime)) {
         
         bool orderOpened = OpenBuyOrder(pairsArray[i], i);
         if(orderOpened) {
            lastOpenTimeArray[i] = currentTime;
            dailyBuyTrades[i]++;
         }
      }

      // Vérification des conditions pour l'ouverture d'un ordre de vente
      if(canOpenSell && 
         (MaxDailySellTradesPerPair == 0 || dailySellTrades[i] < MaxDailySellTradesPerPair) &&
         (MaxSellTradesPerPair == 0 || CountPositions(pairsArray[i], POSITION_TYPE_SELL) < MaxSellTradesPerPair) &&
         (MaxTradesOnAccount == 0 || PositionsTotal() < MaxTradesOnAccount) &&
         (MaxDailyTradesOnAccount == 0 || (dailyBuyTrades[i] + dailySellTrades[i]) < MaxDailyTradesOnAccount) &&
         (currentTime - lastOpenTimeArray[i] >= OpenTime)) {
         
         bool orderOpened = OpenSellOrder(pairsArray[i], i);
         if(orderOpened) {
            lastOpenTimeArray[i] = currentTime;
            dailySellTrades[i]++;
         }
      }
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
      lastDayReset = currentTime;
      ArrayFill(dailyBuyTrades, 0, ArraySize(dailyBuyTrades), 0);
      ArrayFill(dailySellTrades, 0, ArraySize(dailySellTrades), 0);
      dailyProfit = 0;
      dailyProfitPercent = 0;
      dailyInitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // Save initial balance for the day
   }
}

//+------------------------------------------------------------------+
//| Check if we can open a new trade                                  |
//+------------------------------------------------------------------+
bool CanOpenNewTrade(string symbol, int pairIndex) {
   // Check if max daily profit protection is enabled and limit reached
   if(MaxDailyProfitPercent > 0 && dailyProfitPercent >= MaxDailyProfitPercent) {
      if(Debug) {
         Print("Max daily profit reached: ", dailyProfitPercent, "%");
      }
      return false;
   }
   
   // Vérifier si la protection contre le drawdown est activée
   if(!EnableMaxDrawdown) return true;
   
   // Calculer le drawdown actuel
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pairTotalProfit = buyInfoArray[pairIndex].totalProfit + sellInfoArray[pairIndex].totalProfit;
   double drawdownPercent = pairTotalProfit < 0 ? MathAbs(pairTotalProfit) / currentBalance * 100 : 0;
   
   // Vérifier si le drawdown dépasse le seuil d'urgence
   if(CloseAllOnEmergency && drawdownPercent >= EmergencyDrawdownPercent) {
      CloseAllPositions(symbol);
      return false;
   }
   
   // Vérifier si le drawdown dépasse le seuil maximum
   if(drawdownPercent >= MaxDrawdownPercent) {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update trade counters after opening a trade                       |
//+------------------------------------------------------------------+
void UpdateTradeCounters(int pairIndex) {
   // No longer tracking daily trades
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
bool OpenBuyOrder(string symbol, int idx) {
   if(TradeDirection == TRADE_SELL_ONLY) return false;
   
   // Check daily trade limits
   if(!CanOpenNewTrade(symbol, idx)) {
      return false;
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
         double currentLots = CalculateLotSize(symbol, POSITION_TYPE_BUY, buyPositions);
         if(currentLots <= 0) return false;
         
         double positionProfit = buyInfo.totalProfit;
         double sprd = 0.0;
         if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
         string status = "OK";
         string extra = "";
         bool rsiCondition = true;
         double stopLoss = StopLossPoints > 0 ? ask - StopLossPoints * localPoint : 0;
         if(trade.Buy(currentLots, symbol, ask, stopLoss, 0, expertName)) {
            // Update trade counters after successful trade
            UpdateTradeCounters(idx);
            return true;
         } else {
            status = "FAIL";
            extra = IntegerToString(GetLastError());
         }
         LogInfo(symbol, "BUY", localRsi, "B", currentLots, buyPositions, positionProfit, sprd, status, extra);
      }
   } else {
      double sprd = 0.0;
      if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
      LogInfo(symbol, "BUY", localRsi, "B", Lots, buyPositions, buyInfo.totalProfit, sprd, "MAX", "dca");
   }
   buyInfoArray[idx] = buyInfo;
   return false;
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
bool OpenSellOrder(string symbol, int idx) {
   if(TradeDirection == TRADE_BUY_ONLY) return false;
   
   // Check daily trade limits
   if(!CanOpenNewTrade(symbol, idx)) {
      return false;
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
         double currentLots = CalculateLotSize(symbol, POSITION_TYPE_SELL, sellPositions);
         if(currentLots <= 0) return false;
         
         double positionProfit = sellInfo.totalProfit;
         double sprd = 0.0;
         if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
         string status = "OK";
         string extra = "";
         bool rsiCondition = true;
         double stopLoss = StopLossPoints > 0 ? bid + StopLossPoints * localPoint : 0;
         if(trade.Sell(currentLots, symbol, bid, stopLoss, 0, expertName)) {
            // Update trade counters after successful trade
            UpdateTradeCounters(idx);
            return true;
         } else {
            status = "FAIL";
            extra = IntegerToString(GetLastError());
         }
         LogInfo(symbol, "SELL", localRsi, "S", currentLots, sellPositions, positionProfit, sprd, status, extra);
      }
   } else {
      double sprd = 0.0;
      if(!SymbolInfoDouble(symbol, (ENUM_SYMBOL_INFO_DOUBLE)SYMBOL_SPREAD, sprd)) sprd = 0.0;
      LogInfo(symbol, "SELL", localRsi, "S", Lots, sellPositions, sellInfo.totalProfit, sprd, "MAX", "dca");
   }
   sellInfoArray[idx] = sellInfo;
   return false;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on selected method                        |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, ENUM_POSITION_TYPE posType, int currentPositions) {
   double lotSize = Lots;
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   switch(LotCalculationMethod) {
      case LOT_FIXED:
         lotSize = Lots;
         break;
         
      case LOT_RISK_PERCENTAGE:
         if(StopLossPoints > 0) {
            double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            double riskAmount = accountBalance * RiskPercent / 100.0;
            double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
            
            lotSize = NormalizeDouble(riskAmount / (StopLossPoints * tickValue / tickSize), 2);
            
            if(EnableLotMultiplier && currentPositions > 0) {
               lotSize *= MathPow(LotMultiplier, currentPositions);
            }
         }
         break;
   }
   
   // Normalize lot size
   lotSize = MathFloor(lotSize / volumeStep) * volumeStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
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
   globalTotalProfit = 0;  // Use renamed variable
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
   if(!EnableDCA) return;
   // Variables for Buy
   double buyAveragePrice = 0;
   double buyTotalLots = 0;
   int buyPositionCount = 0;
   // Variables for Sell
   double sellAveragePrice = 0;
   double sellTotalLots = 0;
   int sellPositionCount = 0;
   // Calculate averages for Buy and Sell separately
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
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   // Check DCA conditions for Buy if allowed
   if(TradeDirection != TRADE_SELL_ONLY && buyPositionCount > 0) {
      double rsi = rsiCache[idx].lastRsi;
      bool rsiCondition = !UseRsiFilter || ((RsiStrategy == RSI_REVERSAL) ? (rsi < RsiBuyLevel) : (rsi > RsiBuyLevel));
      bool adxCondition = !UseAdxFilter || (adxCache[idx].lastAdx > AdxMinThreshold && adxCache[idx].lastAdx < AdxMaxThreshold);
      bool maCondition = !UseMaFilter || (BuyAboveMa ? (bid > maCache[idx].lastMa) : (bid < maCache[idx].lastMa));
      bool emaRangeCondition = (EmaRangePoints == 0) || (bid < maCache[idx].lastMa - EmaRangePoints * point || bid > maCache[idx].lastMa + EmaRangePoints * point);
      bool bbCondition = !UseBBFilter || (
         BBMode == BB_UPPER_LOWER ? 
            (BuyAboveBB ? (bid > bbCache[idx].upperBand) : (bid < bbCache[idx].lowerBand)) :
            (BuyAboveBB ? (bid > bbCache[idx].middleBand) : (bid < bbCache[idx].middleBand))
      );
      if(rsiCondition && adxCondition && maCondition && emaRangeCondition && bbCondition &&
         (MaxDailyBuyTradesPerPair == 0 || dailyBuyTrades[idx] < MaxDailyBuyTradesPerPair) &&
         (MaxBuyTradesPerPair == 0 || CountPositions(symbol, POSITION_TYPE_BUY) < MaxBuyTradesPerPair) &&
         (MaxTradesOnAccount == 0 || PositionsTotal() < MaxTradesOnAccount) &&
         (MaxDailyTradesOnAccount == 0 || (dailyBuyTrades[idx] + dailySellTrades[idx]) < MaxDailyTradesOnAccount) &&
         (currentTime - lastOpenTimeArray[idx] >= OpenTime)) {  // Ajout de la vérification OpenTime
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
         if(positionsInCurrentBar == 0) {
            OpenBuyOrder(symbol, idx);
            dailyBuyTrades[idx]++;
         }
      }
   }
   // Check DCA conditions for Sell if allowed
   if(TradeDirection != TRADE_BUY_ONLY && sellPositionCount > 0) {
      double rsi = rsiCache[idx].lastRsi;
      bool rsiCondition = !UseRsiFilter || ((RsiStrategy == RSI_REVERSAL) ? (rsi > RsiSellLevel) : (rsi < RsiSellLevel));
      bool adxCondition = !UseAdxFilter || (adxCache[idx].lastAdx > AdxMinThreshold && adxCache[idx].lastAdx < AdxMaxThreshold);
      bool maCondition = !UseMaFilter || (SellBelowMa ? (ask < maCache[idx].lastMa) : (ask > maCache[idx].lastMa));
      bool emaRangeCondition = (EmaRangePoints == 0) || (ask < maCache[idx].lastMa - EmaRangePoints * point || ask > maCache[idx].lastMa + EmaRangePoints * point);
      bool bbCondition = !UseBBFilter || (
         BBMode == BB_UPPER_LOWER ? 
            (SellBelowBB ? (ask < bbCache[idx].lowerBand) : (ask > bbCache[idx].upperBand)) :
            (SellBelowBB ? (ask < bbCache[idx].middleBand) : (ask > bbCache[idx].middleBand))
      );
      if(rsiCondition && adxCondition && maCondition && emaRangeCondition && bbCondition &&
         (MaxDailySellTradesPerPair == 0 || dailySellTrades[idx] < MaxDailySellTradesPerPair) &&
         (MaxSellTradesPerPair == 0 || CountPositions(symbol, POSITION_TYPE_SELL) < MaxSellTradesPerPair) &&
         (MaxTradesOnAccount == 0 || PositionsTotal() < MaxTradesOnAccount) &&
         (MaxDailyTradesOnAccount == 0 || (dailyBuyTrades[idx] + dailySellTrades[idx]) < MaxDailyTradesOnAccount) &&
         (currentTime - lastOpenTimeArray[idx] >= OpenTime)) {  // Ajout de la vérification OpenTime
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
         if(positionsInCurrentBar == 0) {
            OpenSellOrder(symbol, idx);
            dailySellTrades[idx]++;
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
   int yStep = FontSize + 10; // Plus d'espace entre les lignes pour petit écran
   
   // Calculer la largeur nécessaire pour chaque colonne
   int pairWidth = 9;   // Largeur pour la colonne "Pair"
   int rsiWidth = 5;    // Largeur pour la colonne "RSI"
   int adxWidth = 5;    // Largeur pour la colonne "ADX"
   int plWidth = 10;     // Largeur pour la colonne "P/L"
   int maxddWidth = 10;  // Largeur pour la colonne "MaxDD"
   int closedWidth = 10; // Largeur pour la colonne "Closed"
   
   // Calculer la largeur totale nécessaire
   int totalWidth = pairWidth + rsiWidth + adxWidth + plWidth + maxddWidth + closedWidth + 10; // +10 pour les séparateurs
   
   // Ajuster la largeur du panneau si nécessaire
   if(totalWidth * FontSize > PanelWidth) {
      // Réduire proportionnellement la largeur de chaque colonne
      double scaleFactor = (double)PanelWidth / (totalWidth * FontSize);
      pairWidth = (int)(pairWidth * scaleFactor);
      rsiWidth = (int)(rsiWidth * scaleFactor);
      adxWidth = (int)(adxWidth * scaleFactor);
      plWidth = (int)(plWidth * scaleFactor);
      maxddWidth = (int)(maxddWidth * scaleFactor);
      closedWidth = (int)(closedWidth * scaleFactor);
   }
   
   // Table header
   string header = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      adxWidth, "ADX",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   
   // Separator line
   string tableSeparator = StringFormat("%-*s+%*s+%*s+%*s+%*s+%*s",
      pairWidth, "---------",
      rsiWidth, "------",
      adxWidth, "------",
      plWidth, "---------",
      maxddWidth, "---------",
      closedWidth, "---------");
   
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
   
   // Ligne 2: Date et heure du broker
   datetime brokerTime = LocalToBrokerTime(TimeCurrent());
   string brokerDateTime = StringFormat("Broker Time: %s", TimeToString(brokerTime, TIME_DATE|TIME_MINUTES));
   UpdateLabel(prefix + "BrokerTime", brokerDateTime, x, y, TextColor);
   y += yStep;
   
   // Ligne 3: Profit et Drawdown
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double currentProfit = AccountInfoDouble(ACCOUNT_PROFIT);
   double currentDrawdown = (currentBalance - currentEquity) / currentBalance * 100;
   string accountInfo2 = StringFormat("Profit: %10.2f | DD (%%): %4.2f%%", 
      currentProfit, 
      currentDrawdown);
   UpdateLabel(prefix + "AccountInfo2", accountInfo2, x, y, currentProfit > 0 ? clrLime : (currentProfit < 0 ? clrRed : TextColor));
   y += yStep;
   
   // Ligne 4: Nombre total de positions
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
   string headerUsdQuote = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      adxWidth, "ADX",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "UsdQuoteHeader", headerUsdQuote, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorUsdQuote = StringFormat("%-*s+%*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      adxWidth, "--------",
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
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            adxWidth, UseAdxFilter ? DoubleToString(NormalizeDouble(adxCache[i].lastAdx, 2), 2) : "N/A",
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
   string headerUsdBase = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      adxWidth, "ADX",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "UsdBaseHeader", headerUsdBase, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorUsdBase = StringFormat("%-*s+%*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      adxWidth, "--------",
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
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            adxWidth, UseAdxFilter ? DoubleToString(NormalizeDouble(adxCache[i].lastAdx, 2), 2) : "N/A",
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
   string headerOther = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s | %*s",
      pairWidth, "Pair",
      rsiWidth, "RSI",
      adxWidth, "ADX",
      plWidth, "P/L",
      maxddWidth, StringFormat("MaxDD(%s)", accountCurrency),
      closedWidth, "Closed");
   UpdateLabel(prefix + "OtherPairsHeader", headerOther, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparatorOther = StringFormat("%-*s+%*s+%*s+%*s+%*s+%*s+%*s",
      pairWidth, "----------",
      rsiWidth, "--------",
      adxWidth, "--------",
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
         string line = StringFormat("%-*s | %*s | %*s | %*s | %*s | %*s",
            pairWidth, symbol,
            rsiWidth, DoubleToString(NormalizeDouble(currentRsi, 2), 2),
            adxWidth, UseAdxFilter ? DoubleToString(NormalizeDouble(adxCache[i].lastAdx, 2), 2) : "N/A",
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
   
   // Add after the account info section
   if(MaxDailyProfitPercent > 0) {
      string dailyProfitInfo = StringFormat("Daily Profit: %10.2f (%4.2f%%)", dailyProfit, dailyProfitPercent);
      color profitColor = dailyProfitPercent >= MaxDailyProfitPercent ? clrOrange : (dailyProfit > 0 ? clrLime : (dailyProfit < 0 ? clrRed : TextColor));
      UpdateLabel(prefix + "DailyProfit", dailyProfitInfo, x, y, profitColor);
      y += yStep;
   }
   
   // Forcer le redessinage du graphique
   ChartRedraw();
}

// Fonction de log universel
void LogInfo(string sym, string act, double rsi, string dir, double lots, int nbPos, double profit, double sprd, string status, string extra) {
   if(Debug) {
      string msg = StringFormat("%s|%s|RSI:%.1f|%s|L:%.2f|N:%d|P:%.2f|S:%.1f|%s|%s",
         sym, act, rsi, dir, lots, nbPos, profit, sprd, status, extra);
      Print(msg);
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get MA value using MT5's built-in indicator                       |
//+------------------------------------------------------------------+
double GetMA(string symbol, int period, ENUM_MA_METHOD method) {
   // Check if symbol is available
   if(!SymbolSelect(symbol, true)) {
      return -1;
   }
   
   // Get MA indicator handle
   int maHandle = iMA(symbol, MaTimeframe, period, 0, method, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE) {
      return -1;
   }
   
   int maxWait = 5000; // Maximum 5 seconds
   int waited = 0;
   while(BarsCalculated(maHandle) < period + 1) {
      Sleep(100);
      waited += 100;
      if(waited >= maxWait) {
         IndicatorRelease(maHandle);
         return -1;
      }
   }
   
   // Copy MA value
   double maBuffer[];
   ArraySetAsSeries(maBuffer, true);
   
   int copied = CopyBuffer(maHandle, 0, 0, period + 1, maBuffer);
   
   if(copied != period + 1) {
      IndicatorRelease(maHandle);
      return -1;
   }
   
   // Check if value is valid
   if(maBuffer[0] == 0 || maBuffer[0] == EMPTY_VALUE) {
      IndicatorRelease(maHandle);
      return -1;
   }
   
   // Store value in cache
   int idx = GetPairIndex(symbol);
   if(idx >= 0) {
      maCache[idx].lastMa = maBuffer[0];
      maCache[idx].lastBarTime = iTime(symbol, PERIOD_CURRENT, 0);
      maCache[idx].initialized = true;
   }
   
   IndicatorRelease(maHandle);
   return maBuffer[0];
}

//+------------------------------------------------------------------+
//| Update daily profit                                               |
//+------------------------------------------------------------------+
void UpdateDailyProfit() {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Calculate daily profit as the difference between current equity and initial balance
   dailyProfit = currentEquity - dailyInitialBalance;
   
   // Calculate daily profit percentage
   dailyProfitPercent = (dailyProfit / dailyInitialBalance) * 100;
   
   if(Debug) {
      Print("Daily Profit: ", dailyProfit, " (", dailyProfitPercent, "%)");
   }
}

//+------------------------------------------------------------------+
//| Get Bollinger Bands values using MT5's built-in indicator         |
//+------------------------------------------------------------------+
double GetBB(string symbol, int period, double deviation, ENUM_BB_MODE mode) {
   // Check if symbol is available
   if(!SymbolSelect(symbol, true)) {
      return -1;
   }
   
   // Get BB indicator handle
   int bbHandle = iBands(symbol, BBTimeframe, period, 0, deviation, PRICE_CLOSE);
   if(bbHandle == INVALID_HANDLE) {
      return -1;
   }
   
   int maxWait = 5000; // Maximum 5 seconds
   int waited = 0;
   while(BarsCalculated(bbHandle) < period + 1) {
      Sleep(100);
      waited += 100;
      if(waited >= maxWait) {
         IndicatorRelease(bbHandle);
         return -1;
      }
   }
   
   // Copy BB values
   double upperBuffer[];
   double middleBuffer[];
   double lowerBuffer[];
   
   ArraySetAsSeries(upperBuffer, true);
   ArraySetAsSeries(middleBuffer, true);
   ArraySetAsSeries(lowerBuffer, true);
   
   int copiedUpper = CopyBuffer(bbHandle, 1, 0, period + 1, upperBuffer);
   int copiedMiddle = CopyBuffer(bbHandle, 0, 0, period + 1, middleBuffer);
   int copiedLower = CopyBuffer(bbHandle, 2, 0, period + 1, lowerBuffer);
   
   if(copiedUpper != period + 1 || copiedMiddle != period + 1 || copiedLower != period + 1) {
      IndicatorRelease(bbHandle);
      return -1;
   }
   
   // Check if values are valid
   if(upperBuffer[0] == 0 || upperBuffer[0] == EMPTY_VALUE ||
      middleBuffer[0] == 0 || middleBuffer[0] == EMPTY_VALUE ||
      lowerBuffer[0] == 0 || lowerBuffer[0] == EMPTY_VALUE) {
      IndicatorRelease(bbHandle);
      return -1;
   }
   
   // Store values in cache
   int idx = GetPairIndex(symbol);
   if(idx >= 0) {
      bbCache[idx].upperBand = upperBuffer[0];
      bbCache[idx].middleBand = middleBuffer[0];
      bbCache[idx].lowerBand = lowerBuffer[0];
      bbCache[idx].lastBarTime = iTime(symbol, PERIOD_CURRENT, 0);
      bbCache[idx].initialized = true;
   }
   
   IndicatorRelease(bbHandle);
   
   // Return appropriate band based on mode
   switch(mode) {
      case BB_UPPER_LOWER:
         return BuyAboveBB ? upperBuffer[0] : lowerBuffer[0];
      case BB_MIDDLE:
         return middleBuffer[0];
      default:
         return -1;
   }
}

//+------------------------------------------------------------------+
//| Calculate total account profit                                     |
//+------------------------------------------------------------------+
double CalculateTotalAccountProfit() {
   double accountProfit = 0;
   // Profits des positions ouvertes
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic) {
            accountProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   // Profits des deals fermés depuis le dernier reset
   HistorySelect(lastProfitReset, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic) {
         accountProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   return accountProfit;
}

//+------------------------------------------------------------------+
//| Check if profit target reached                                     |
//+------------------------------------------------------------------+
bool CheckProfitTarget() {
   static datetime lastProfitTargetCheck = 0;
   if(TimeCurrent() - lastProfitTargetCheck >= 1) { // Check once per second
      double totalAccountProfit = CalculateTotalAccountProfit();
      if(totalAccountProfit >= ProfitTargetAmount) {
         Print(TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + 
               "   PROFIT TARGET REACHED! Total Profit: " + DoubleToString(totalAccountProfit, 2) + " USD");
         // Close all positions for each symbol
         for(int i = 0; i < ArraySize(pairsArray); i++) {
            CloseAllPositions(pairsArray[i]);
            buyInfoArray[i].totalProfit = 0;
            sellInfoArray[i].totalProfit = 0;
            buyInfoArray[i].initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            sellInfoArray[i].initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            lastOpenTimeArray[i] = TimeCurrent();
         }
         lastProfitReset = TimeCurrent(); // RESET ICI
         lastProfitTargetCheck = TimeCurrent();
         return true;
      }
      lastProfitTargetCheck = TimeCurrent();
   }
   return false;
}
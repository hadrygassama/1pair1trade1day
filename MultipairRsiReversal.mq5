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

// Trading direction enum
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

// Expert parameters
input group    "=== Trading Settings ==="
input string   Pairs = "EURUSD,GBPUSD,USDJPY,AUDUSD,NZDUSD,USDCAD,EURGBP,EURJPY,GBPJPY,AUDJPY";  // Pairs list
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input int      Magic = 548762;         // Magic
input double   Lots = 0.05;            // Lots
input int      OpenTime = 30;          // Time between orders
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input int      MaxSpread = 40;         // Max spread (pips)
input int      PriceStepPoints = 10;   // Price step (points)
input bool     EnableMinEntryDistance = true;  // Activer distance min entre positions
input int MinEntryDistancePoints = 30; // Min distance entre positions (points)

input group    "=== RSI Settings ==="
input bool     UseRsiFilter = true;    // Use RSI
input int      RsiPeriod = 14;         // Period
input int      RsiBuyLevel = 30;       // Buy level
input int      RsiSellLevel = 70;      // Sell level

input group    "=== Stop Loss/Take Profit Settings ==="
input int      TakeProfitPoints = 300;  // Take Profit
input int      TrailingStopPoints = 200;  // Trailing Stop
input int      TrailingStartPoints = 100;  // Trailing Start

input group    "=== DCA Settings ==="
input bool     EnableMaxDCAPositions = false;  // Limit DCA
input int      MaxDCAPositions = 100;    // Max DCA positions
input bool     EnableLotMultiplier = true;  // Enable lot multiplier for DCA
input double   LotMultiplier = 1.5;      // DCA lot multiplier
input double   MaxLotEntry = 0.5;        // Maximum lot size for DCA entries

input group    "=== Interface Settings ==="
input bool     Info = true;            // Show panel
input ENUM_BASE_CORNER PanelCorner = CORNER_LEFT_UPPER;  // Corner
input int      PanelXDistance = 20;    // X distance
input int      PanelYDistance = 20;    // Y distance
input int      PanelWidth = 500;       // Panel width
input int      FontSize = 12;          // Font size
input color    TextColor = clrWhite;   // Text color

input group    "=== Time Settings ==="
input bool     AutoDetectBrokerOffset = true;  // Auto-detect broker time offset
input bool     BrokerIsAheadOfGMT = false;     // Broker time is ahead of GMT (e.g. GMT+2)
input int      ManualBrokerOffset = 3;         // Manual broker GMT offset in hours (always positive)

// Global variables
CTrade trade;
string expertName = "1pair1trade1day";
datetime lastOpenTime = 0;
double lastBidPrice = 0;
double initialBalance = 0;
double maxBuyDD = 0;
double maxSellDD = 0;
double maxTotalDD = 0;
string pairsArray[];  // Array to store currency pairs
MqlDateTime timeStruct;
datetime currentTime;
double currentSpread;
double spreadInPips;
double rsi;
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
int panelWidth = PanelWidth;  // Using input parameter

// Structure to store position information
struct PositionInfo {
   double avgPrice;
   double totalProfit;
   double totalLots;
   int count;
   double currentDD;
   double maxDD;
   double closedProfit;
};

// Global variables for position tracking
PositionInfo buyInfo;
PositionInfo sellInfo;
double totalClosedProfit = 0;  // Profit total des trades fermés pour le compte

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
   
   Print("Detected broker time offset: GMT", (diffHours >= 0 ? "+" : ""), diffHours);
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
      Print("Error: Symbol ", symbol, " is not available");
      return -1;
   }
   
   // Check if symbol is active
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL) {
      Print("Warning: Symbol ", symbol, " is not fully tradeable");
   }
   
   // Get RSI indicator handle
   int rsiHandle = iRSI(symbol, PERIOD_CURRENT, period, price);
   if(rsiHandle == INVALID_HANDLE) {
      Print("Error: Failed to create RSI indicator for ", symbol);
      return -1;
   }
   
   int maxWait = 5000; // Maximum 5 seconds
   int waited = 0;
   while(BarsCalculated(rsiHandle) < period + 1) {
      Sleep(100);
      waited += 100;
      if(waited >= maxWait) {
         Print("Error: RSI initialization timeout for ", symbol);
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
         Print("Warning: Retry ", tries, " to copy RSI buffer for ", symbol);
         Sleep(100);
      }
   }
   
   if(copied != period + 1) {
      Print("Error: Failed to copy RSI buffer for ", symbol, 
            " - Error: ", GetLastError(), 
            " - Copied: ", copied,
            " - Buffer size: ", ArraySize(rsiBuffer),
            " - Period: ", period,
            " - Price: ", EnumToString(price));
      IndicatorRelease(rsiHandle);
      return -1;
   }
   
   // Check if value is valid
   if(rsiBuffer[0] == 0 || rsiBuffer[0] == EMPTY_VALUE) {
      Print("Warning: Invalid RSI value for ", symbol, 
            " - Value: ", rsiBuffer[0],
            " - Period: ", period,
            " - Price: ", EnumToString(price));
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
      Print("Error: Could not find valid currency codes in ", basicPair);
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
      Print("Warning: Could not detect broker format for ", basicPair, ". Using default format.");
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
      Print("Error: Lots must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(OpenTime <= 0) {
      Print("Error: OpenTime must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeStartHour < 0 || TimeStartHour > 23) {
      Print("Error: TimeStartHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeEndHour < 0 || TimeEndHour > 23) {
      Print("Error: TimeEndHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TimeStartHour >= TimeEndHour) {
      Print("Error: TimeStartHour must be less than TimeEndHour");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxSpread <= 0) {
      Print("Error: MaxSpread must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(PriceStepPoints <= 0) {
      Print("Error: PriceStepPoints must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate RSI parameters
   if(RsiPeriod <= 0) {
      Print("Error: RsiPeriod must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(RsiBuyLevel < 0 || RsiBuyLevel > 100) {
      Print("Error: RsiBuyLevel must be between 0 and 100");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(RsiSellLevel < 0 || RsiSellLevel > 100) {
      Print("Error: RsiSellLevel must be between 0 and 100");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate stop loss/take profit parameters
   if(TrailingStopPoints < 0) {
      Print("Error: TrailingStopPoints must be greater than or equal to 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TrailingStartPoints < 0) {
      Print("Error: TrailingStartPoints must be greater than or equal to 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate interface parameters
   if(FontSize <= 0) {
      Print("Error: FontSize must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate pairs string
   if(StringLen(Pairs) == 0) {
      Print("Error: Pairs string is empty");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize pairs array
   StringSplit(Pairs, ',', pairsArray);
   if(ArraySize(pairsArray) == 0) {
      Print("Error: No valid pairs found in Pairs string");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Validate each pair
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string normalizedPair = NormalizePairName(pairsArray[i]);
      if(!SymbolSelect(normalizedPair, true)) {
         Print("Error: Symbol ", normalizedPair, " is not available");
         return INIT_PARAMETERS_INCORRECT;
      }
      // Update array with normalized name
      pairsArray[i] = normalizedPair;
   }
   
   // Validate DCA parameters
   if(MaxDCAPositions <= 0) {
      Print("Error: MaxDCAPositions must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxDCAPositions > 5) {
      Print("Warning: MaxDCAPositions is set to ", MaxDCAPositions, " which is higher than recommended (1-5). This may lead to excessive risk exposure.");
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(Magic);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxBuyDD = 0;
   maxSellDD = 0;
   maxTotalDD = 0;
   
   Print("EA initialized successfully - Magic: ", Magic);
   Print("Trading pairs: ", Pairs);
   Print("Initial balance: ", initialBalance);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "EA_Info_");
   Print("EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Get current time using GMT
   currentTime = TimeGMT();
   TimeToStruct(currentTime, timeStruct);
   
   // Update info panel first
   if(Info) UpdateInfoPanel();
   
   // Check trading hours (using broker time)
   int currentHour = timeStruct.hour;
   int currentMinute = timeStruct.min;
   
   // Convert start and end times to minutes for easier comparison
   int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
   int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
   int currentTimeInMinutes = currentHour * 60 + currentMinute;
   
   // Check if current time is within trading hours
   if(startTimeInMinutes <= endTimeInMinutes) {
      // Normal trading session (same day)
      if(currentTimeInMinutes < startTimeInMinutes || currentTimeInMinutes >= endTimeInMinutes) return;
   } else {
      // Trading session spans midnight
      if(currentTimeInMinutes < startTimeInMinutes && currentTimeInMinutes >= endTimeInMinutes) return;
   }
   
   // Process each currency pair
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string currentSymbol = pairsArray[i];
      
      // Get symbol properties once per iteration
      point = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
      double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
      
      // Check spread
      currentSpread = ask - bid;
      spreadInPips = currentSpread / (point * 10);
      if(spreadInPips > MaxSpread) continue;
      
      // Initialize trade conditions
      canOpenBuy = false;
      canOpenSell = false;
      
      // Check if enough time has passed since last trade for this specific pair
      if(currentTime >= lastOpenTime + OpenTime) {
         // Check buy conditions
         if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
            bool rsiCondition = true;
            if(UseRsiFilter) {
               rsi = GetRSI(currentSymbol, RsiPeriod, PRICE_CLOSE);
               rsiCondition = (rsi < RsiBuyLevel);  // Buy when RSI is below 30 (oversold)
               datetime brokerTime = LocalToBrokerTime(TimeCurrent());
               Print("[", TimeToString(brokerTime, TIME_DATE|TIME_SECONDS), "] Buy check - Symbol: ", currentSymbol, 
                     " RSI: ", rsi, " RSI Condition: ", rsiCondition, 
                     " Price Condition: ", (bid - PriceStepPoints * point >= lastBidPrice),
                     " Last Bid: ", lastBidPrice, " Current Bid: ", bid);
            }
            
            if(bid - PriceStepPoints * point >= lastBidPrice && rsiCondition) {
               canOpenBuy = true;
               Print("Buy condition met for ", currentSymbol, " - RSI: ", rsi);
               lastBidPrice = bid;  // Update reference price only when condition is met
            }
         }
         
         // Check sell conditions
         if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
            bool rsiCondition = true;
            if(UseRsiFilter) {
               rsi = GetRSI(currentSymbol, RsiPeriod, PRICE_CLOSE);
               rsiCondition = (rsi > RsiSellLevel);  // Sell when RSI is above 70 (overbought)
               datetime brokerTime = LocalToBrokerTime(TimeCurrent());
               Print("[", TimeToString(brokerTime, TIME_DATE|TIME_SECONDS), "] Sell check - Symbol: ", currentSymbol, 
                     " RSI: ", rsi, " RSI Condition: ", rsiCondition,
                     " Price Condition: ", (bid + PriceStepPoints * point <= lastBidPrice),
                     " Last Bid: ", lastBidPrice, " Current Bid: ", bid);
            }
            
            if(bid + PriceStepPoints * point <= lastBidPrice && rsiCondition) {
               canOpenSell = true;
               Print("Sell condition met for ", currentSymbol, " - RSI: ", rsi);
               lastBidPrice = bid;  // Update reference price only when condition is met
            }
         }
         
         // Open new trades if conditions are met
         if(canOpenBuy || canOpenSell) {
            lastOpenTime = currentTime;
         }
      }
      
      // Open new trades if conditions are met
      if(canOpenBuy) OpenBuyOrder(currentSymbol);
      if(canOpenSell) OpenSellOrder(currentSymbol);
      
      // Update trailing stops and check take profits
      UpdateTrailingStops(currentSymbol, bid, ask);
      
      // Check DCA conditions
      CheckDCAConditions(currentSymbol);
   }
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder(string symbol) {
   // Check if Buy is allowed
   if(TradeDirection == TRADE_SELL_ONLY) return;
   
   int buyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
   
   // Only check MaxDCAPositions if EnableMaxDCAPositions is true
   if(!EnableMaxDCAPositions || buyPositions < MaxDCAPositions) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
      
      if(positionsInCurrentBar == 0) {
         double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         
         // Vérification du RSI en premier
         bool rsiCondition = true;
         if(UseRsiFilter) {
            rsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
            rsiCondition = (rsi < RsiBuyLevel);
            if(!rsiCondition) {
               Print("RSI condition non respectée pour BUY sur ", symbol, " - RSI: ", rsi);
               return;
            }
         }
         
         // Vérification de la distance minimale APRÈS le RSI
         if(!IsMinEntryDistanceRespected(symbol, ask, POSITION_TYPE_BUY, MinEntryDistancePoints)) {
            Print("Nouvelle entrée BUY trop proche d'une position existante sur ", symbol);
            return;
         }
         
         // Get symbol volume step
         double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         
         // Calculate lot size based on DCA multiplier
         double currentLots = Lots;
         if(EnableLotMultiplier && buyPositions > 0) {
            currentLots = Lots * MathPow(LotMultiplier, buyPositions);
            if(currentLots > MaxLotEntry) {
               currentLots = MaxLotEntry;
            }
         }
         
         // Round lot size to the nearest valid step
         currentLots = MathFloor(currentLots / volumeStep) * volumeStep;
         
         // Ensure lot size is within symbol limits
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         currentLots = MathMax(minLot, MathMin(maxLot, currentLots));
         
         if(!trade.Buy(currentLots, symbol, ask, 0, 0, expertName)) {
            Print("Buy order failed for ", symbol, ". Error: ", GetLastError());
         }
         else {
            Print("Buy order placed successfully for ", symbol, " with lots: ", currentLots);
         }
      }
   }
   else {
      Print("Maximum DCA Buy positions (", MaxDCAPositions, ") reached for ", symbol);
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder(string symbol) {
   // Check if Sell is allowed
   if(TradeDirection == TRADE_BUY_ONLY) return;
   
   int sellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
   
   // Only check MaxDCAPositions if EnableMaxDCAPositions is true
   if(!EnableMaxDCAPositions || sellPositions < MaxDCAPositions) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
      
      if(positionsInCurrentBar == 0) {
         double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         
         // Vérification du RSI en premier
         bool rsiCondition = true;
         if(UseRsiFilter) {
            rsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
            rsiCondition = (rsi > RsiSellLevel);
            if(!rsiCondition) {
               Print("RSI condition non respectée pour SELL sur ", symbol, " - RSI: ", rsi);
               return;
            }
         }
         
         // Vérification de la distance minimale APRÈS le RSI
         if(!IsMinEntryDistanceRespected(symbol, bid, POSITION_TYPE_SELL, MinEntryDistancePoints)) {
            Print("Nouvelle entrée SELL trop proche d'une position existante sur ", symbol);
            return;
         }
         
         // Get symbol volume step
         double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         
         // Calculate lot size based on DCA multiplier
         double currentLots = Lots;
         if(EnableLotMultiplier && sellPositions > 0) {
            currentLots = Lots * MathPow(LotMultiplier, sellPositions);
            if(currentLots > MaxLotEntry) {
               currentLots = MaxLotEntry;
            }
         }
         
         // Round lot size to the nearest valid step
         currentLots = MathFloor(currentLots / volumeStep) * volumeStep;
         
         // Ensure lot size is within symbol limits
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         currentLots = MathMax(minLot, MathMin(maxLot, currentLots));
         
         if(!trade.Sell(currentLots, symbol, bid, 0, 0, expertName)) {
            Print("Sell order failed for ", symbol, ". Error: ", GetLastError());
         }
         else {
            Print("Sell order placed successfully for ", symbol, " with lots: ", currentLots);
         }
      }
   }
   else {
      Print("Maximum DCA Sell positions (", MaxDCAPositions, ") reached for ", symbol);
   }
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
   info.maxDD = 0;
   info.closedProfit = 0;
   
   double maxProfit = 0;
   double currentProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            
            currentProfit = PositionGetDouble(POSITION_PROFIT);
            info.totalProfit += currentProfit;
            
            if(currentProfit > maxProfit) {
               maxProfit = currentProfit;
            }
            
            double currentDD = maxProfit - currentProfit;
            if(currentDD > info.currentDD) {
               info.currentDD = currentDD;
            }
            
            if(currentDD > info.maxDD) {
               info.maxDD = currentDD;
            }
         }
      }
   }
   
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
// Met à jour les statistiques globales des positions
// - Calcule les statistiques pour chaque symbole
// - Met à jour le profit total et le drawdown total
// - Met à jour les statistiques pour les positions d'achat et de vente
void UpdatePositionStatistics() {
   // Reset global variables
   totalProfit = 0;
   currentTotalDD = 0;
   
   // Calculate statistics for each symbol
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string symbol = pairsArray[i];
      
      // Calculate Buy positions info
      CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfo);
      
      // Calculate Sell positions info
      CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfo);
      
      // Update total profit
      totalProfit += buyInfo.totalProfit + sellInfo.totalProfit;
   }
   
   // Calculate total drawdown
   if(totalProfit < 0) {
      currentTotalDD = MathAbs(totalProfit) / initialBalance * 100;
      maxTotalDD = MathMax(maxTotalDD, currentTotalDD);
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
   
   // Gestion des profits et trailing stops pour les positions Buy
   if(buyPositionCount > 0) {
      double buyProfitInPoints = (bid - buyAveragePrice) / localPoint;
      
      // Vérifier si le Take Profit est atteint pour le groupe Buy
      if(TakeProfitPoints > 0 && buyProfitInPoints >= TakeProfitPoints) {
         Print("Take Profit reached for Buy positions of ", symbol, " - Profit: ", buyProfitInPoints, " points");
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
                  
                  if(currentSL < buyAveragePrice || currentSL == 0) {
                     if(bid - (TrailingStopPoints + TrailingStartPoints) * localPoint >= buyAveragePrice) {
                        trade.PositionModify(PositionGetTicket(i),
                                           buyAveragePrice + TrailingStartPoints * localPoint,
                                           PositionGetDouble(POSITION_TP));
                     }
                  }
                  else if(currentSL >= buyAveragePrice) {
                     if(bid - TrailingStopPoints * localPoint > currentSL) {
                        trade.PositionModify(PositionGetTicket(i),
                                           bid - TrailingStopPoints * localPoint,
                                           PositionGetDouble(POSITION_TP));
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
         Print("Take Profit reached for Sell positions of ", symbol, " - Profit: ", sellProfitInPoints, " points");
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
                  
                  if(currentSL > sellAveragePrice || currentSL == 0) {
                     if(ask + (TrailingStopPoints + TrailingStartPoints) * localPoint <= sellAveragePrice) {
                        trade.PositionModify(PositionGetTicket(i),
                                           sellAveragePrice - TrailingStartPoints * localPoint,
                                           PositionGetDouble(POSITION_TP));
                     }
                  }
                  else if(currentSL <= sellAveragePrice) {
                     if(ask + TrailingStopPoints * localPoint < currentSL) {
                        trade.PositionModify(PositionGetTicket(i),
                                           ask + TrailingStopPoints * localPoint,
                                           PositionGetDouble(POSITION_TP));
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
               Print("Failed to close position ", PositionGetTicket(i), " for ", symbol, ". Error: ", GetLastError());
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
void CheckDCAConditions(string symbol) {
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
      // Vérifier le filtre RSI si activé
      bool rsiCondition = true;
      if(UseRsiFilter) {
         rsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         rsiCondition = (rsi < RsiBuyLevel);  // Buy when RSI is below buy level
      }
      
      if(bid + PriceStepPoints * localPoint <= buyAveragePrice && 
         (!EnableMaxDCAPositions || buyPositionCount < MaxDCAPositions) &&
         rsiCondition) {  // Ajout de la condition RSI
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
         if(positionsInCurrentBar == 0) {
            Print("DCA Buy condition met for ", symbol, " - Price dropped below average by ", PriceStepPoints, " points, RSI: ", rsi);
            OpenBuyOrder(symbol);
         }
      }
   }
   
   // Vérifier les conditions DCA pour Sell si autorisé
   if(TradeDirection != TRADE_BUY_ONLY && sellPositionCount > 0) {
      // Vérifier le filtre RSI si activé
      bool rsiCondition = true;
      if(UseRsiFilter) {
         rsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         rsiCondition = (rsi > RsiSellLevel);  // Sell when RSI is above sell level
      }
      
      if(ask - PriceStepPoints * localPoint >= sellAveragePrice && 
         (!EnableMaxDCAPositions || sellPositionCount < MaxDCAPositions) &&
         rsiCondition) {  // Ajout de la condition RSI
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
         if(positionsInCurrentBar == 0) {
            Print("DCA Sell condition met for ", symbol, " - Price rose above average by ", PriceStepPoints, " points, RSI: ", rsi);
            OpenSellOrder(symbol);
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
//| Update Info Panel                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel() {
   if(!Info) return;
   
   string prefix = "EA_Info_";
   int x = PanelXDistance;
   int y = PanelYDistance;
   int yStep = FontSize + 4;
   
   // Informations globales du compte
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double drawdown = (balance - equity) / balance * 100;
   
   // Ligne 1: Balance et Equity
   string accountInfo1 = StringFormat("Balance: %.2f | Equity: %.2f", balance, equity);
   UpdateLabel(prefix + "AccountInfo1", accountInfo1, x, y, TextColor);
   y += yStep;
   
   // Ligne 2: Profit et Drawdown
   string accountInfo2 = StringFormat("Profit: %.2f | DD: %.2f%% | Max DD: %.2f%%", profit, drawdown, maxTotalDD);
   UpdateLabel(prefix + "AccountInfo2", accountInfo2, x, y, profit > 0 ? clrLime : (profit < 0 ? clrRed : TextColor));
   y += yStep;
   
   // Ligne 3: Nombre total de positions
   int totalPositions = PositionsTotal();
   string accountInfo3 = StringFormat("Total Positions: %d", totalPositions);
   UpdateLabel(prefix + "AccountInfo3", accountInfo3, x, y, TextColor);
   y += yStep;
   
   // Ligne séparatrice
   string separator = "----------------------------------------";
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
   string header = StringFormat("%-10s | %6s | %7s | %6s | %9s | %9s",
      "Pair", "RSI", "P/L", "DD", "Max DD", "Closed");
   UpdateLabel(prefix + "UsdQuoteHeader", header, x, y, TextColor);
   y += yStep;
   
   // Separator line
   string tableSeparator = StringFormat("%s",
      "----------+--------+---------+--------+-----------+-----------");
   UpdateLabel(prefix + "UsdQuoteTableSeparator", tableSeparator, x, y, TextColor);
   y += yStep;
   
   // Display information for each XXX/USD pair
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a XXX/USD pair
      if(StringSubstr(cleanSymbol, 3, 3) == "USD") {
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfo);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfo);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-10s | %6.2f | %7.2f | %6.2f | %9.2f | %9.2f",
            symbol, currentRsi,
            buyInfo.totalProfit + sellInfo.totalProfit,
            buyInfo.currentDD + sellInfo.currentDD,
            MathMax(buyInfo.maxDD, sellInfo.maxDD),
            buyInfo.closedProfit + sellInfo.closedProfit);
         
         // Determine color based on total profit
         double totalPairProfit = buyInfo.totalProfit + sellInfo.totalProfit + buyInfo.closedProfit + sellInfo.closedProfit;
         color lineColor = totalPairProfit == 0 ? TextColor : (totalPairProfit > 0 ? clrLime : clrRed);
         
         UpdateLabel(prefix + "UsdQuote_" + IntegerToString(i), line, x, y, lineColor);
         y += yStep;
      }
   }
   
   y += yStep * 2;  // Extra space between sections
   
   // ====== USD/XXX PAIRS TABLE (USD as base) ======
   
   UpdateLabel(prefix + "UsdBaseTitle", "USD/XXX PAIRS (USD as base)", x, y, clrCrimson);
   y += yStep;
   
   // Table header
   UpdateLabel(prefix + "UsdBaseHeader", header, x, y, TextColor);
   y += yStep;
   
   // Separator line
   UpdateLabel(prefix + "UsdBaseTableSeparator", tableSeparator, x, y, TextColor);
   y += yStep;
   
   // Display information for each USD/XXX pair
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a USD/XXX pair
      if(StringSubstr(cleanSymbol, 0, 3) == "USD") {
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfo);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfo);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-10s | %6.2f | %7.2f | %6.2f | %9.2f | %9.2f",
            symbol, currentRsi,
            buyInfo.totalProfit + sellInfo.totalProfit,
            buyInfo.currentDD + sellInfo.currentDD,
            MathMax(buyInfo.maxDD, sellInfo.maxDD),
            buyInfo.closedProfit + sellInfo.closedProfit);
         
         // Determine color based on total profit
         double totalPairProfit = buyInfo.totalProfit + sellInfo.totalProfit + buyInfo.closedProfit + sellInfo.closedProfit;
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
   UpdateLabel(prefix + "OtherPairsHeader", header, x, y, TextColor);
   y += yStep;
   
   // Separator line
   UpdateLabel(prefix + "OtherPairsTableSeparator", tableSeparator, x, y, TextColor);
   y += yStep;
   
   // Display information for other pairs
   for(int i = 0; i < ArraySize(pairsArray); i++) {
      string symbol = pairsArray[i];
      string cleanSymbol = symbol;
      StringReplace(cleanSymbol, "/", "");
      StringReplace(cleanSymbol, "-", "");
      StringReplace(cleanSymbol, "_", "");
      StringReplace(cleanSymbol, "|", "");
      StringReplace(cleanSymbol, ".", "");
      
      // Check if it's a pair without USD
      if(StringFind(cleanSymbol, "USD") == -1) {
         // Calculate position information
         CalculatePositionInfo(symbol, POSITION_TYPE_BUY, buyInfo);
         CalculatePositionInfo(symbol, POSITION_TYPE_SELL, sellInfo);
         
         // Get RSI value
         double currentRsi = GetRSI(symbol, RsiPeriod, PRICE_CLOSE);
         
         // Create line for this pair
         string line = StringFormat("%-10s | %6.2f | %7.2f | %6.2f | %9.2f | %9.2f",
            symbol, currentRsi,
            buyInfo.totalProfit + sellInfo.totalProfit,
            buyInfo.currentDD + sellInfo.currentDD,
            MathMax(buyInfo.maxDD, sellInfo.maxDD),
            buyInfo.closedProfit + sellInfo.closedProfit);
         
         // Determine color based on total profit
         double totalPairProfit = buyInfo.totalProfit + sellInfo.totalProfit + buyInfo.closedProfit + sellInfo.closedProfit;
         color lineColor = totalPairProfit == 0 ? TextColor : (totalPairProfit > 0 ? clrLime : clrRed);
         
         UpdateLabel(prefix + "Other_" + IntegerToString(i), line, x, y, lineColor);
         y += yStep;
      }
   }
   
   // Forcer le redessinage du graphique
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      Print("Error creating label: ", GetLastError());
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
//| Vérifie que la distance minimale est respectée entre le prix d'entrée proposé et toutes les positions existantes de la même direction |
//+------------------------------------------------------------------+
bool IsMinEntryDistanceRespected(string symbol, double entryPrice, ENUM_POSITION_TYPE posType, int minDistancePoints) {
    // Si la vérification est désactivée, retourner true
    if(!EnableMinEntryDistance) return true;
    
    double localPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetString(POSITION_SYMBOL) == symbol &&
               PositionGetInteger(POSITION_TYPE) == posType) {
                double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double distance = MathAbs(entryPrice - posPrice) / localPoint;
                if(distance < minDistancePoints) {
                    Print("Distance minimale non respectée: ", distance, " points avec position existante");
                    return false;
                }
            }
        }
    }
    return true;
} 
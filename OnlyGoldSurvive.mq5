//+------------------------------------------------------------------+
//|                                                           OnlyGoldSurvive.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.1pair1trade1day.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Indicators\Indicators.mqh>

// Enum for trading direction
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

// Expert parameters
input group    "=== Trading Direction ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Trading direction
input int      Magic = 123456;         // Expert Advisor ID

input group    "=== Position Sizing ==="
input double   Lots = 0.5;             // Base lot size
input double   LotMultiplier = 1.5;    // Lot size multiplier
input double   MaxLot = 1.5;           // Maximum lot size
input bool     EnableMaxPosition = false;     // Enable position limits
input int      MaxBuyPositions = 30;    // Maximum Buy positions
input int      MaxSellPositions = 30;   // Maximum Sell positions

input group    "=== Entry Conditions ==="
input int      PipsStep = 20;          // Price step in pips
input int      MaxSpread = 50;         // Maximum spread in pips
input bool     UseMinDistance = false;  // Minimum distance check
input int      MinDistancePips = 30;   // Minimum distance in pips
input bool     UseMinTime = false;      // Minimum time check
input int      OpenTime = 60;          // Minimum time in seconds

input group    "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Trading start hour (Broker GMT time)
input int      TimeStartMinute = 0;    // Trading start minute (Broker GMT time)
input int      TimeEndHour = 23;       // Trading end hour (Broker GMT time)
input int      TimeEndMinute = 59;     // Trading end minute (Broker GMT time)

input group    "=== Bollinger Bands Filter ==="
input bool     UseBollingerFilter = true;  // Enable BB filter
input int      BBPeriod = 20;          // BB period
input double   BBDeviation = 2.0;      // BB deviation
input ENUM_APPLIED_PRICE BBPrice = PRICE_CLOSE; // BB price type
input int      MinDistanceFromBB = 10;  // Minimum distance from BB in pips

input group    "=== ADX Filter ==="
input bool     UseADXFilter = false;     // Enable ADX filter
input int      ADXPeriod = 14;          // ADX period
input double   MinADX = 25.0;           // Minimum ADX value
input double   MaxADX = 100.0;           // Maximum ADX value

input group    "=== RSI Filter ==="
input bool     UseRSIFilter = false;     // Enable RSI filter
input int      RSIPeriod = 14;          // RSI period
input double   RSIBuyStart = 30.0;      // RSI Buy start level
input double   RSIBuyEnd = 70.0;        // RSI Buy end level
input double   RSISellStart = 30.0;     // RSI Sell start level
input double   RSISellEnd = 70.0;       // RSI Sell end level

input group    "=== Exit Conditions ==="
input int      Tral = 5;             // Trailing stop in pips
input int      TralStart = 20;        // Trailing stop start in pips
input double   TakeProfit = 30;       // Take profit in pips

input group    "=== Interface Settings ==="
input bool     Info = true;            // Show information panel
input int      FontSize = 12;          // Panel font size
input color    TextColor = clrWhite;   // Panel text color
input bool     ShowTradeLogs = false;  // Show trade logs

// Global variables
CTrade trade;
CiBands bollingerBands;
CiADX adxIndicator;  // Add ADX indicator
CiRSI rsiIndicator;  // Add RSI indicator
string expertName = "OnlyGoldSurvive";
datetime lastOpenTime = 0;
datetime lastBuyPositionTime = 0;      // Time of the last Buy position
datetime lastSellPositionTime = 0;     // Time of the last Sell position
double lastBidPrice = 0;
double initialBalance = 0;
double maxBuyDD = 0;
double maxSellDD = 0;
double maxTotalDD = 0;
double totalPriceMovement = 0;  // Variable to track total price movement
datetime lastLogTime = 0;        // Variable for log filtering
double lastSpread = 0;            // Variable for log filtering
double lastLoggedMovement = 0;    // Variable for log filtering

// Variables globales pour le cache
double cachedBuyProfit = 0;
double cachedSellProfit = 0;
double cachedBuyLots = 0;
double cachedSellLots = 0;
int cachedBuyPositions = 0;
int cachedSellPositions = 0;
datetime lastCacheUpdate = 0;
int cacheUpdateInterval = 5; // Augmentation de l'intervalle à 5 secondes
bool cacheNeedsUpdate = true; // Nouvelle variable pour suivre si le cache doit être mis à jour

// Variables globales pour le cache des indicateurs
double cachedUpperBand = 0;
double cachedLowerBand = 0;
double cachedADXValue = 0;
double cachedRSIValue = 0;
datetime lastIndicatorUpdate = 0;
int indicatorUpdateInterval = 5; // Mise à jour des indicateurs toutes les 5 secondes

// Variables globales pour le cache des drawdowns
double cachedBuyDD = 0;
double cachedSellDD = 0;
double cachedTotalDD = 0;
datetime lastDDUpdate = 0;
int DDUpdateInterval = 5; // Mise à jour des drawdowns toutes les 5 secondes

// Variables globales pour le cache des conditions
bool cachedCanTradeBuy = false;
bool cachedCanTradeSell = false;
datetime lastConditionCheck = 0;
int conditionCheckInterval = 5; // Vérification des conditions toutes les 5 secondes

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(Magic);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxBuyDD = 0;
   maxSellDD = 0;
   maxTotalDD = 0;
   
   // Initialize Bollinger Bands
   if(!bollingerBands.Create(_Symbol, PERIOD_CURRENT, BBPeriod, 0, BBDeviation, BBPrice)) {
      PrintFormat("Error creating Bollinger Bands: %d", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize ADX
   if(UseADXFilter && !adxIndicator.Create(_Symbol, PERIOD_CURRENT, ADXPeriod)) {
      PrintFormat("Error creating ADX indicator: %d", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize RSI
   if(UseRSIFilter && !rsiIndicator.Create(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE)) {
      PrintFormat("Error creating RSI indicator: %d", GetLastError());
      return(INIT_FAILED);
   }
   
   PrintFormat("EA initialized - Magic: %d", Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "EA_Info_");
   PrintFormat("EA deinitialized - Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Update panel first
   if(Info) UpdateInfoPanel();
   
   // Update indicators, drawdowns and conditions
   UpdateIndicators();
   UpdateDrawdowns();
   CheckTradingConditions();
   
   // Get current price
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Vérification de la connexion au serveur
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
      PrintStatusLine();
      return;
   }
   
   // Check trading hours using server GMT time
   datetime currentTime = TimeCurrent();  // Server local time
   datetime gmtTime = TimeGMT();         // Server GMT time (trading server time)
   datetime localTime = TimeLocal();     // Computer local time
   
   MqlDateTime timeStruct;
   TimeToStruct(gmtTime, timeStruct);
   
   int gmtHour = timeStruct.hour;
   int gmtMinute = timeStruct.min;
   
   // Convert trading hours to minutes for comparison
   int currentTimeInMinutes = gmtHour * 60 + gmtMinute;
   int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
   int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
   
   if(currentTimeInMinutes < startTimeInMinutes || currentTimeInMinutes >= endTimeInMinutes) {
      PrintStatusLine();
      return;
   }
   
   // Check spread
   double currentSpread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Get the number of digits for the symbol
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Calculate spread in pips based on the number of digits
   double spreadInPips;
   if(digits == 2 || digits == 3) {
      // For pairs with 2 or 3 digits (like XAUUSD)
      spreadInPips = currentSpread * 10;
   } else if(digits == 4 || digits == 5) {
      // For pairs with 4 or 5 digits (like EURUSD)
      spreadInPips = currentSpread * 10000;
   } else {
      // Default case, should not happen with standard pairs
      spreadInPips = currentSpread / _Point;
   }
   
   if(spreadInPips > MaxSpread) {
      PrintStatusLine();
      return;
   }
   
   // Open new trades if conditions are met
   if(cachedCanTradeBuy) {
      OpenBuyOrder();
      lastBidPrice = currentBid;
      totalPriceMovement = 0;
      lastOpenTime = currentTime;
   }
   if(cachedCanTradeSell) {
      OpenSellOrder();
      lastBidPrice = currentBid;
      totalPriceMovement = 0;
      lastOpenTime = currentTime;
   }
   
   // Update trailing stops and check take profits
   UpdateTrailingStops();
   
   // Check DCA conditions only for allowed directions
   CheckDCAConditions();
   
   // Print status line every second
   if(currentTime - lastLogTime >= 1) {
      PrintStatusLine();
      lastLogTime = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder() {
   // Check if Buy is allowed
   if(TradeDirection == TRADE_SELL_ONLY) return;
   
   // Check minimum delay
   datetime currentTime = TimeCurrent();
   if(UseMinTime && currentTime - lastBuyPositionTime < OpenTime) {
      return;
   }
   
   int totalBuyPositions = CountPositions(POSITION_TYPE_BUY);
   int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
   
   // Check position limit if enabled
   if(EnableMaxPosition && totalBuyPositions >= MaxBuyPositions) {
      return;
   }
   
   if(positionsInCurrentBar == 0) {
      // Get symbol properties
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      // Calculate lot size with multiplier
      double calculatedLots = Lots * MathPow(LotMultiplier, totalBuyPositions);
      calculatedLots = MathMin(calculatedLots, MaxLot); // Ensure we don't exceed MaxLot
      
      // Round to the nearest valid lot size
      calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;
      calculatedLots = MathMax(calculatedLots, minLot); // Ensure we don't go below minimum
      
      // Check minimum distance from last position
      if(CheckMinimumDistance(POSITION_TYPE_BUY, MinDistancePips)) {
         // Get current price and check if we already have a position at this level
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool hasPositionAtLevel = false;
         
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                  PositionGetString(POSITION_SYMBOL) == _Symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  
                  double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double priceDiff = MathAbs(currentBid - positionPrice) / _Point;
                  
                  if(priceDiff < 10) { // Less than 1 pip difference
                     hasPositionAtLevel = true;
                     break;
                  }
               }
            }
         }
         
         if(!hasPositionAtLevel) {
            string comment = expertName;
            if(trade.Buy(calculatedLots, _Symbol, 0, 0, 0, comment)) {
               lastBuyPositionTime = currentTime; // Update time of last Buy position
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder() {
   // Check if Sell is allowed
   if(TradeDirection == TRADE_BUY_ONLY) return;
   
   // Check minimum delay
   datetime currentTime = TimeCurrent();
   if(UseMinTime && currentTime - lastSellPositionTime < OpenTime) {
      return;
   }
   
   int totalSellPositions = CountPositions(POSITION_TYPE_SELL);
   int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
   
   // Check position limit if enabled
   if(EnableMaxPosition && totalSellPositions >= MaxSellPositions) {
      return;
   }
   
   if(positionsInCurrentBar == 0) {
      // Get symbol properties
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      // Calculate lot size with multiplier
      double calculatedLots = Lots * MathPow(LotMultiplier, totalSellPositions);
      calculatedLots = MathMin(calculatedLots, MaxLot); // Ensure we don't exceed MaxLot
      
      // Round to the nearest valid lot size
      calculatedLots = MathFloor(calculatedLots / lotStep) * lotStep;
      calculatedLots = MathMax(calculatedLots, minLot); // Ensure we don't go below minimum
      
      // Check minimum distance from last position
      if(CheckMinimumDistance(POSITION_TYPE_SELL, MinDistancePips)) {
         // Get current price and check if we already have a position at this level
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         bool hasPositionAtLevel = false;
         
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                  PositionGetString(POSITION_SYMBOL) == _Symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                  
                  double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double priceDiff = MathAbs(currentAsk - positionPrice) / _Point;
                  
                  if(priceDiff < 10) { // Less than 1 pip difference
                     hasPositionAtLevel = true;
                     break;
                  }
               }
            }
         }
         
         if(!hasPositionAtLevel) {
            string comment = expertName;
            if(trade.Sell(calculatedLots, _Symbol, 0, 0, 0, comment)) {
               lastSellPositionTime = currentTime; // Update time of last Sell position
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Minimum Distance                                             |
//+------------------------------------------------------------------+
bool CheckMinimumDistance(ENUM_POSITION_TYPE positionType, int minDistancePips) {
   if(!UseMinDistance) return true;  // Skip distance check if disabled
   
   double currentPrice = positionType == POSITION_TYPE_BUY ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            
            double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double distanceInPips = MathAbs(currentPrice - positionPrice) / (_Point * 10);
            
            if(distanceInPips < minDistancePips) {
               return false;
            }
         }
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Count Positions                                                    |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE positionType) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
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
int CountPositionsInCurrentBar(ENUM_POSITION_TYPE positionType) {
   int count = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime >= currentBarTime) {
               count++;
            }
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Update Trailing Stops                                              |
//+------------------------------------------------------------------+
void UpdateTrailingStops() {
   // Variables for Buy positions
   double buyTotalProfit = 0;
   double buyAveragePrice = 0;
   int buyPositionCount = 0;
   double buyTotalLots = 0;
   
   // Variables for Sell positions
   double sellTotalProfit = 0;
   double sellAveragePrice = 0;
   int sellPositionCount = 0;
   double sellTotalLots = 0;
   
   // First pass: calculate averages and profits
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyTotalProfit += positionProfit;
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellTotalProfit += positionProfit;
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
            }
         }
      }
   }
   
   // Calculate weighted average prices
   if(buyPositionCount > 0) buyAveragePrice /= buyTotalLots;
   if(sellPositionCount > 0) sellAveragePrice /= sellTotalLots;
   
   // Manage Buy positions independently
   if(buyPositionCount > 0) {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double buyProfitInPoints = (currentBid - buyAveragePrice) / _Point;
      
      // Check if Buy group has reached take profit
      if(buyProfitInPoints >= TakeProfit) {
         if(ShowTradeLogs) PrintFormat("Closing all Buy positions - Total profit in points: %.2f", buyProfitInPoints);
         ClosePositionsInDirection(POSITION_TYPE_BUY);
      } else {
         // Update trailing stops for all Buy positions
         if(Tral != 0) {
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                     
                     double currentSL = PositionGetDouble(POSITION_SL);
                     double newSL = 0;
                     
                     if(currentSL < buyAveragePrice || currentSL == 0) {
                        if(currentBid - (Tral + TralStart) * _Point >= buyAveragePrice) {
                           newSL = buyAveragePrice + TralStart * _Point;
                        }
                     }
                     else if(currentSL >= buyAveragePrice) {
                        if(currentBid - Tral * _Point > currentSL) {
                           newSL = currentBid - Tral * _Point;
                        }
                     }
                     
                     // Only modify if we have a valid new stop loss
                     if(newSL > 0) {
                        // Get symbol properties for stop level
                        double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                        double minStop = currentBid - stopLevel;
                        
                        // Ensure stop loss is not too close to current price
                        if(newSL < minStop) {
                           newSL = minStop;
                        }
                        
                        // Only modify if the new stop loss is different from current
                        if(MathAbs(newSL - currentSL) > _Point) {
                           trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                        }
                     }
                  }
               }
            }
         }
      }
   }
   
   // Manage Sell positions independently
   if(sellPositionCount > 0) {
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sellProfitInPoints = (sellAveragePrice - currentAsk) / _Point;
      
      // Check if Sell group has reached take profit
      if(sellProfitInPoints >= TakeProfit) {
         if(ShowTradeLogs) PrintFormat("Closing all Sell positions - Total profit in points: %.2f", sellProfitInPoints);
         ClosePositionsInDirection(POSITION_TYPE_SELL);
      } else {
         // Update trailing stops for all Sell positions
         if(Tral != 0) {
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                     
                     double currentSL = PositionGetDouble(POSITION_SL);
                     double newSL = 0;
                     
                     if(currentSL > sellAveragePrice || currentSL == 0) {
                        if(currentAsk + (Tral + TralStart) * _Point <= sellAveragePrice) {
                           newSL = sellAveragePrice - TralStart * _Point;
                        }
                     }
                     else if(currentSL <= sellAveragePrice) {
                        if(currentAsk + Tral * _Point < currentSL) {
                           newSL = currentAsk + Tral * _Point;
                        }
                     }
                     
                     // Only modify if we have a valid new stop loss
                     if(newSL > 0) {
                        // Get symbol properties for stop level
                        double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
                        double maxStop = currentAsk + stopLevel;
                        
                        // Ensure stop loss is not too close to current price
                        if(newSL > maxStop) {
                           newSL = maxStop;
                        }
                        
                        // Only modify if the new stop loss is different from current
                        if(MathAbs(newSL - currentSL) > _Point) {
                           trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                        }
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
void ClosePositionsInDirection(ENUM_POSITION_TYPE positionType) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check DCA Conditions                                              |
//+------------------------------------------------------------------+
void CheckDCAConditions() {
   // Variables for Buy
   double buyAveragePrice = 0;
   double buyTotalLots = 0;
   int buyPositionCount = 0;
   double buyTotalProfit = 0;
   
   // Variables for Sell
   double sellAveragePrice = 0;
   double sellTotalLots = 0;
   int sellPositionCount = 0;
   double sellTotalProfit = 0;
   
   // Calculate averages and profits for Buy and Sell separately
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
               buyTotalProfit += positionProfit;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
               sellTotalProfit += positionProfit;
            }
         }
      }
   }
   
   // Calculate weighted average prices
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Update Bollinger Bands
   bollingerBands.Refresh();
   double upperBand = bollingerBands.Upper(0);
   double lowerBand = bollingerBands.Lower(0);
   
   // Update ADX if enabled
   bool adxCondition = true;
   if(UseADXFilter) {
      adxIndicator.Refresh();
      double adxValue = adxIndicator.Main(0);
      adxCondition = adxValue >= MinADX && adxValue <= MaxADX;
   }
   
   // Check DCA conditions for Buy if allowed
   if(TradeDirection != TRADE_SELL_ONLY && buyPositionCount > 0) {
      // Only DCA if:
      // 1. Position is in loss
      // 2. Price is above upper band - min distance (same as normal entry)
      // 3. Price is at least PipsStep away from average price
      // 4. We haven't reached position limit
      // 5. ADX condition is met (if enabled)
      if(buyTotalProfit < 0 && 
         currentBid > (upperBand - (MinDistanceFromBB * _Point * 10)) && 
         currentBid + PipsStep * _Point <= buyAveragePrice && 
         buyPositionCount < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2 &&
         adxCondition) {
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
         if(positionsInCurrentBar == 0) {
            OpenBuyOrder();
         }
      }
   }
   
   // Check DCA conditions for Sell if allowed
   if(TradeDirection != TRADE_BUY_ONLY && sellPositionCount > 0) {
      // Only DCA if:
      // 1. Position is in loss
      // 2. Price is below lower band + min distance (same as normal entry)
      // 3. Price is at least PipsStep away from average price
      // 4. We haven't reached position limit
      // 5. ADX condition is met (if enabled)
      if(sellTotalProfit < 0 && 
         currentAsk < (lowerBand + (MinDistanceFromBB * _Point * 10)) && 
         currentAsk - PipsStep * _Point >= sellAveragePrice && 
         sellPositionCount < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2 &&
         adxCondition) {
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
         if(positionsInCurrentBar == 0) {
            OpenSellOrder();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Info Panel                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel() {
   if(!Info) return;
   
   UpdatePositionCache();
   
   string prefix = "EA_Info_";
   int x = 10;
   int y = 20;
   int yStep = FontSize + 10;
   int totalLines = 0;  // Compteur pour le nombre total de lignes
   
   ObjectsDeleteAll(0, prefix);
   
   // Display EA status
   CreateLabel(prefix + "Title", "=== EA Status ===", x, y, TextColor);
   y += yStep;
   totalLines++;
   
   // Display current spread with dynamic color
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = spread / (_Point * 10);
   color spreadColor = GetDynamicColor(spreadInPips, MaxSpread, 0);
   CreateLabel(prefix + "Spread", StringFormat("Spread: %.1f pips", spreadInPips), x, y, spreadColor);
   y += yStep;
   totalLines++;
   
   // Display ADX value if enabled
   if(UseADXFilter) {
      UpdateIndicators(); // Make sure ADX is up to date
      color adxColor = GetDynamicColor(cachedADXValue, MaxADX, MinADX);
      CreateLabel(prefix + "ADX", StringFormat("ADX: %.1f", cachedADXValue), x, y, adxColor);
      y += yStep;
      totalLines++;
   }
   
   // Display account information
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = equity - balance;
   double profitPercent = (profit / balance) * 100;
   
   CreateLabel(prefix + "Balance", StringFormat("Balance: %.2f", balance), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "Equity", StringFormat("Equity: %.2f", equity), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "Profit", StringFormat("Profit: %.2f (%.2f%%)", profit, profitPercent), 
              x, y, profit >= 0 ? clrLime : clrRed);
   y += yStep;
   totalLines++;
   
   // Calculate drawdowns using cached values
   double currentBuyDD = cachedBuyDD;
   double currentSellDD = cachedSellDD;
   double totalProfit = cachedBuyProfit + cachedSellProfit;
   double currentTotalDD = cachedTotalDD;
   
   // Update max drawdowns
   if(currentBuyDD > maxBuyDD) maxBuyDD = currentBuyDD;
   if(currentSellDD > maxSellDD) maxSellDD = currentSellDD;
   if(currentTotalDD > maxTotalDD) maxTotalDD = currentTotalDD;
   
   // Display Buy information
   CreateLabel(prefix + "BuyPositions", StringFormat("Buy Positions: %d (%.2f lots)", 
              cachedBuyPositions, cachedBuyLots), x, y, clrLime);
   y += yStep;
   totalLines++;
   if(cachedBuyPositions > 0) {
      CreateLabel(prefix + "BuyProfit", StringFormat("Buy Profit: %.2f", cachedBuyProfit), x, y, clrLime);
      y += yStep;
      totalLines++;
      CreateLabel(prefix + "BuyDD", StringFormat("Buy DD: %.2f%% (Max: %.2f%%)", 
                 currentBuyDD, maxBuyDD), x, y, currentBuyDD > 0 ? clrOrange : clrLime);
      y += yStep;
      totalLines++;
   }
   
   // Display Sell information
   CreateLabel(prefix + "SellPositions", StringFormat("Sell Positions: %d (%.2f lots)", 
              cachedSellPositions, cachedSellLots), x, y, clrRed);
   y += yStep;
   totalLines++;
   if(cachedSellPositions > 0) {
      CreateLabel(prefix + "SellProfit", StringFormat("Sell Profit: %.2f", cachedSellProfit), x, y, clrRed);
      y += yStep;
      totalLines++;
      CreateLabel(prefix + "SellDD", StringFormat("Sell DD: %.2f%% (Max: %.2f%%)", 
                 currentSellDD, maxSellDD), x, y, currentSellDD > 0 ? clrOrange : clrRed);
      y += yStep;
      totalLines++;
   }
   
   // Display total information
   y += yStep;
   totalLines++;
   int totalPositions = cachedBuyPositions + cachedSellPositions;
   double totalLots = cachedBuyLots + cachedSellLots;
   CreateLabel(prefix + "TotalPositions", StringFormat("Total Positions: %d (%.2f lots)", 
              totalPositions, totalLots), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "TotalProfit", StringFormat("Total Profit: %.2f", totalProfit), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "TotalDD", StringFormat("Total DD: %.2f%% (Max: %.2f%%)", 
              currentTotalDD, maxTotalDD), x, y, currentTotalDD > 0 ? clrOrange : TextColor);
   y += yStep;
   totalLines++;
   
   // Display next trade time
   if(lastOpenTime > 0) {
      datetime nextOpenTime = lastOpenTime + 60;
      if(nextOpenTime > TimeCurrent()) {
         CreateLabel(prefix + "NextTrade", StringFormat("Next Trade: %s", 
                    TimeToString(nextOpenTime, TIME_MINUTES|TIME_SECONDS)), x, y, TextColor);
         y += yStep;
         totalLines++;
      }
   }
   
   // Create background rectangle with dynamic height
   int panelHeight = totalLines * yStep + 20; // 20 pixels de marge
   CreateRectangle(prefix + "Background", x - 5, 15, 300, panelHeight, clrBlack, 200);
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      PrintFormat("Error creating label: %d", GetLastError());
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Check if a direction is in loss                                    |
//+------------------------------------------------------------------+
bool IsDirectionInLoss(ENUM_POSITION_TYPE positionType) {
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   
   return totalProfit < 0;
}

//+------------------------------------------------------------------+
//| Calculate total profit of all positions                            |
//+------------------------------------------------------------------+
double CalculateTotalProfit() {
   double totalProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Check if we should stop trading in a direction                    |
//+------------------------------------------------------------------+
bool ShouldStopTradingDirection(ENUM_POSITION_TYPE direction) {
    return false;
}

//+------------------------------------------------------------------+
//| Close All Positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Print Status Line                                                  |
//+------------------------------------------------------------------+
void PrintStatusLine() {
   // Get current prices and bands
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (currentAsk - currentBid) / _Point / 10;  // Convert to pips
   
   // Get Bollinger Bands
   bollingerBands.Refresh();
   double upperBand = bollingerBands.Upper(0);
   double lowerBand = bollingerBands.Lower(0);
   
   // Calculate trading lines
   double buyLine = upperBand - (MinDistanceFromBB * _Point * 10);
   double sellLine = lowerBand + (MinDistanceFromBB * _Point * 10);
   
   // Get positions info
   int buyPositions = CountPositions(POSITION_TYPE_BUY);
   int sellPositions = CountPositions(POSITION_TYPE_SELL);
   double buyProfit = 0;
   double sellProfit = 0;
   double buyLots = 0;
   double sellLots = 0;
   
   // Calculate profits and lots
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyProfit += PositionGetDouble(POSITION_PROFIT);
               buyLots += positionLots;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellProfit += PositionGetDouble(POSITION_PROFIT);
               sellLots += positionLots;
            }
         }
      }
   }
   
   // Calculate drawdowns
   double buyDD = buyProfit < 0 ? MathAbs(buyProfit) / initialBalance * 100 : 0;
   double sellDD = sellProfit < 0 ? MathAbs(sellProfit) / initialBalance * 100 : 0;
   
   // Get ADX value if enabled
   double adxValue = 0;
   if(UseADXFilter) {
      adxIndicator.Refresh();
      adxValue = adxIndicator.Main(0);
   }
   
   // Get RSI value if enabled
   double rsiValue = 0;
   if(UseRSIFilter) {
      rsiIndicator.Refresh();
      rsiValue = rsiIndicator.Main(0);
   }
   
   // Print single line with all important info
   PrintFormat("Bid: %.5f | BuyLine: %.5f | SellLine: %.5f | Buy: %d(%.2f/%.2f) [DD:%.2f%%] | Sell: %d(%.2f/%.2f) [DD:%.2f%%] | Spread: %.1f | ADX: %.1f | RSI: %.1f",
         currentBid, buyLine, sellLine, 
         buyPositions, buyProfit, buyLots, buyDD,
         sellPositions, sellProfit, sellLots, sellDD,
         spread, adxValue, rsiValue);
}

//+------------------------------------------------------------------+
//| Create Rectangle for Panel Background                              |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color clr, int transparency) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
      PrintFormat("Error creating rectangle: %d", GetLastError());
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Get Dynamic Color based on value range                             |
//+------------------------------------------------------------------+
color GetDynamicColor(double value, double maxValue, double minValue) {
   if(value >= maxValue) return clrRed;
   if(value <= minValue) return clrRed;
   
   double range = maxValue - minValue;
   double position = (value - minValue) / range;
   
   if(position < 0.5) {
      // From red to yellow
      return clrYellow;
   } else {
      // From yellow to green
      return clrGreen;
   }
}

//+------------------------------------------------------------------+
//| Update Position Cache                                              |
//+------------------------------------------------------------------+
void UpdatePositionCache() {
   datetime currentTime = TimeCurrent();
   
   // Vérifier si une mise à jour est nécessaire
   if(!cacheNeedsUpdate && currentTime - lastCacheUpdate < cacheUpdateInterval) {
      return;
   }
   
   // Réinitialiser les valeurs
   cachedBuyProfit = 0;
   cachedSellProfit = 0;
   cachedBuyLots = 0;
   cachedSellLots = 0;
   cachedBuyPositions = 0;
   cachedSellPositions = 0;
   
   // Mettre à jour les valeurs
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               cachedBuyProfit += positionProfit;
               cachedBuyLots += positionLots;
               cachedBuyPositions++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               cachedSellProfit += positionProfit;
               cachedSellLots += positionLots;
               cachedSellPositions++;
            }
         }
      }
   }
   
   lastCacheUpdate = currentTime;
   cacheNeedsUpdate = false;
}

//+------------------------------------------------------------------+
//| Marquer le cache comme nécessitant une mise à jour                 |
//+------------------------------------------------------------------+
void MarkCacheForUpdate() {
   cacheNeedsUpdate = true;
}

//+------------------------------------------------------------------+
//| Update Indicators                                                  |
//+------------------------------------------------------------------+
void UpdateIndicators() {
   datetime currentTime = TimeCurrent();
   if(currentTime - lastIndicatorUpdate < indicatorUpdateInterval) return;
   
   if(UseBollingerFilter) {
      bollingerBands.Refresh();
      cachedUpperBand = bollingerBands.Upper(0);
      cachedLowerBand = bollingerBands.Lower(0);
   }
   
   if(UseADXFilter) {
      adxIndicator.Refresh();
      cachedADXValue = adxIndicator.Main(0);
   }
   
   if(UseRSIFilter) {
      rsiIndicator.Refresh();
      cachedRSIValue = rsiIndicator.Main(0);
   }
   
   lastIndicatorUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| Update Drawdowns                                                  |
//+------------------------------------------------------------------+
void UpdateDrawdowns() {
   datetime currentTime = TimeCurrent();
   if(currentTime - lastDDUpdate < DDUpdateInterval) return;
   
   UpdatePositionCache();
   
   // Get current balance
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calculate drawdowns based on current balance
   if(cachedBuyProfit < 0) {
      cachedBuyDD = MathAbs(cachedBuyProfit) / currentBalance * 100;
   } else {
      cachedBuyDD = 0;
   }
   
   if(cachedSellProfit < 0) {
      cachedSellDD = MathAbs(cachedSellProfit) / currentBalance * 100;
   } else {
      cachedSellDD = 0;
   }
   
   double totalProfit = cachedBuyProfit + cachedSellProfit;
   if(totalProfit < 0) {
      cachedTotalDD = MathAbs(totalProfit) / currentBalance * 100;
   } else {
      cachedTotalDD = 0;
   }
   
   // Update max drawdowns
   if(cachedBuyDD > maxBuyDD) {
      maxBuyDD = cachedBuyDD;
   }
   if(cachedSellDD > maxSellDD) {
      maxSellDD = cachedSellDD;
   }
   if(cachedTotalDD > maxTotalDD) {
      maxTotalDD = cachedTotalDD;
   }
   
   lastDDUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| Check Trading Conditions                                          |
//+------------------------------------------------------------------+
void CheckTradingConditions() {
   datetime currentTime = TimeCurrent();
   if(currentTime - lastConditionCheck < conditionCheckInterval) return;
   
   // Reset conditions
   cachedCanTradeBuy = false;
   cachedCanTradeSell = false;
   
   // Get current price
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Check conditions based on chosen direction
   if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
      bool bollingerCondition = true;
      if(UseBollingerFilter) {
         double upperBandMinusPips = cachedUpperBand - (MinDistanceFromBB * _Point * 10);
         bollingerCondition = currentBid > upperBandMinusPips;
      }
      
      if(bollingerCondition) {
         // Vérifier si on peut trader Buy
         cachedCanTradeBuy = !ShouldStopTradingDirection(POSITION_TYPE_BUY);
         
         // Vérifier la condition RSI si activée
         if(UseRSIFilter && cachedCanTradeBuy) {
            rsiIndicator.Refresh();
            double rsiValue = rsiIndicator.Main(0);
            cachedCanTradeBuy = rsiValue >= RSIBuyStart && rsiValue <= RSIBuyEnd;
         }
      }
   }
   
   if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
      bool bollingerCondition = true;
      if(UseBollingerFilter) {
         double lowerBandPlusPips = cachedLowerBand + (MinDistanceFromBB * _Point * 10);
         bollingerCondition = currentBid < lowerBandPlusPips;
      }
      
      if(bollingerCondition) {
         // Vérifier si on peut trader Sell
         cachedCanTradeSell = !ShouldStopTradingDirection(POSITION_TYPE_SELL);
         
         // Vérifier la condition RSI si activée
         if(UseRSIFilter && cachedCanTradeSell) {
            rsiIndicator.Refresh();
            double rsiValue = rsiIndicator.Main(0);
            cachedCanTradeSell = rsiValue >= RSISellStart && rsiValue <= RSISellEnd;
         }
      }
   }
   
   lastConditionCheck = currentTime;
}
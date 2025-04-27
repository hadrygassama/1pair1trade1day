//+------------------------------------------------------------------+
//|                                                           EA_new.mq5 |
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
input double   Lots = 0.1;             // Base lot size
input double   LotMultiplier = 1.5;    // Lot size multiplier
input double   MaxLot = 1.0;           // Maximum lot size
input int      MaxBuyPositions = 30;    // Maximum Buy positions
input int      MaxSellPositions = 30;   // Maximum Sell positions

input group    "=== Entry Conditions ==="
input bool     UseMinDistance = false;  // Minimum distance check
input int      MinDistancePips = 30;   // Minimum distance in pips
input bool     UseMinTime = false;      // Minimum time check
input int      OpenTime = 60;          // Minimum time in seconds
input int      PipsStep = 20;          // Price step in pips
input int      MaxSpread = 50;         // Maximum spread in pips

input group    "=== Trading Hours ==="
input int      BrokerGMTOffset = 3;    // Broker GMT offset
input int      TimeStartHour = 0;      // Trading start hour (GMT)
input int      TimeStartMinute = 0;    // Trading start minute
input int      TimeEndHour = 23;       // Trading end hour (GMT)
input int      TimeEndMinute = 59;     // Trading end minute

input group    "=== Bollinger Bands Filter ==="
input bool     UseBollingerFilter = true;  // Enable Bollinger Bands filter
input int      BBPeriod = 20;          // Bollinger Bands period
input double   BBDeviation = 2.0;      // Bollinger Bands deviation
input ENUM_APPLIED_PRICE BBPrice = PRICE_CLOSE; // Bollinger Bands price type
input int      MinDistanceFromBB = 10;  // Minimum distance from Bollinger Bands in pips

input group    "=== ADX Filter ==="
input bool     UseADXFilter = true;     // Enable ADX filter
input int      ADXPeriod = 14;          // ADX period
input double   MinADX = 25.0;           // Minimum ADX value
input double   MaxADX = 50.0;           // Maximum ADX value

input group    "=== RSI Filter ==="
input bool     UseRSIFilter = false;     // Enable RSI filter
input int      RSIPeriod = 14;          // RSI period
input double   RSIOverbought = 70.0;    // RSI overbought level
input double   RSIOversold = 30.0;      // RSI oversold level

input group    "=== Exit Conditions ==="
input int      Tral = 5;             // Trailing stop in pips
input int      TralStart = 20;        // Trailing stop start in pips
input double   TakeProfit = 30;       // Take profit in pips

input group    "=== Interface Settings ==="
input bool     Info = true;            // Show information panel
input int      FontSize = 12;          // Panel font size
input color    TextColor = clrWhite;   // Panel text color
input bool     ShowTradeLogs = false;  // Show trade logs

input group    "=== Anti Drawdown Settings ==="
input bool     UseAntiDrawdown = true;     // Enable anti-drawdown system
input bool     UseWeightedLotProfit = true; // Use profit per weighted lot instead of fixed currency
input double   MinTotalProfitToAvoidDD = 50.0;         // Minimum total profit in currency to avoid drawdown
input double   MinProfitPerWeightedLot = 10.0;         // Minimum profit in pips per weighted lot to avoid drawdown

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
   
   // Check trading hours
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Adjust broker time to GMT
   int brokerHour = timeStruct.hour;
   int brokerMinute = timeStruct.min;
   
   // Convert broker time to GMT
   int gmtHour = brokerHour - BrokerGMTOffset;
   if(gmtHour < 0) gmtHour += 24;
   if(gmtHour >= 24) gmtHour -= 24;
   
   // Convert trading hours to minutes for comparison
   int currentTimeInMinutes = gmtHour * 60 + brokerMinute;
   int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
   int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
   
   if(currentTimeInMinutes < startTimeInMinutes || currentTimeInMinutes >= endTimeInMinutes) {
      PrintStatusLine();
      return;
   }
   
   // Check spread
   double currentSpread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = currentSpread / (_Point * 10);  // Convert to pips (1 pip = 10 points)
   
   if(spreadInPips > MaxSpread) {
      PrintStatusLine();
      return;
   }
   
   // Update ADX
   if(UseADXFilter) {
      adxIndicator.Refresh();
   }
   
   // Update RSI
   if(UseRSIFilter) {
      rsiIndicator.Refresh();
   }
   
   // Initialize trade conditions
   bool canOpenBuy = false;
   bool canOpenSell = false;
   
   // Check time conditions for new trades
   if(lastOpenTime == 0) {
      lastOpenTime = currentTime;
      lastBidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      totalPriceMovement = 0;
   }
   
   // Check price movements for new trades
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double priceMovement = MathAbs(currentBid - lastBidPrice) / (_Point * 10);  // Movement in pips
   totalPriceMovement += priceMovement;
   
   // Update Bollinger Bands
   bollingerBands.Refresh();
   double upperBand = bollingerBands.Upper(0);
   double lowerBand = bollingerBands.Lower(0);
   
   // Check if price is inside Bollinger Bands
   bool isInsideBands = currentBid >= lowerBand && currentBid <= upperBand;
   
   // Count existing positions
   int buyPositions = CountPositions(POSITION_TYPE_BUY);
   int sellPositions = CountPositions(POSITION_TYPE_SELL);
   
   // Check ADX conditions
   bool adxCondition = true;
   if(UseADXFilter) {
      double adxValue = adxIndicator.Main(0);
      adxCondition = adxValue >= MinADX && adxValue <= MaxADX;
   }
   
   // Check RSI conditions
   bool rsiCondition = true;
   if(UseRSIFilter) {
      double rsiValue = rsiIndicator.Main(0);
      rsiCondition = rsiValue <= RSIOverbought && rsiValue >= RSIOversold;
   }
   
   // Check conditions based on chosen direction
   if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
      if(UseBollingerFilter) {
         // Calculate upper band minus 10 pips
         double upperBandMinusPips = upperBand - (MinDistanceFromBB * _Point * 10);
         
         // Debug logs for Buy conditions
         Print("=== DEBUG: Buy Conditions ===");
         Print("Current Bid: ", currentBid);
         Print("Upper Band: ", upperBand);
         Print("Upper Band - MinDistance: ", upperBandMinusPips);
         Print("Distance from Upper Band: ", (upperBand - currentBid) / _Point / 10, " pips");
         Print("Should enter Buy: ", currentBid > upperBandMinusPips ? "YES" : "NO");
         Print("TradeDirection: ", TradeDirection == TRADE_BUY_ONLY ? "BUY_ONLY" : "BOTH");
         Print("UseBollingerFilter: ", UseBollingerFilter ? "YES" : "NO");
         Print("ADX Condition: ", adxCondition ? "YES" : "NO");
         Print("RSI Condition: ", rsiCondition ? "YES" : "NO");
         Print("Spread Condition: ", spreadInPips <= MaxSpread ? "YES" : "NO");
         Print("Time Condition: ", currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes < endTimeInMinutes ? "YES" : "NO");
         Print("AntiDrawdown: ", !UseAntiDrawdown || !ShouldStopTradingDirection(POSITION_TYPE_BUY) ? "YES" : "NO");
         
         // Check if price is above (upper band - 10 pips)
         if(currentBid > upperBandMinusPips) {
            // Check if we should stop trading Buy based on Anti Drawdown
            if(!UseAntiDrawdown || !ShouldStopTradingDirection(POSITION_TYPE_BUY)) {
               canOpenBuy = true;
               Print("=== ENTRY BUY TRIGGERED ===");
               Print("Reason: Price above upper band - min distance");
            }
         }
      }
   }
   
   if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
      if(UseBollingerFilter) {
         // Calculate lower band plus 10 pips
         double lowerBandPlusPips = lowerBand + (MinDistanceFromBB * _Point * 10);
         
         // Debug logs for Sell conditions
         Print("=== DEBUG: Sell Conditions ===");
         Print("Current Bid: ", currentBid);
         Print("Lower Band: ", lowerBand);
         Print("Lower Band + MinDistance: ", lowerBandPlusPips);
         Print("Distance from Lower Band: ", (currentBid - lowerBand) / _Point / 10, " pips");
         Print("Should enter Sell: ", currentBid < lowerBandPlusPips ? "YES" : "NO");
         Print("TradeDirection: ", TradeDirection == TRADE_SELL_ONLY ? "SELL_ONLY" : "BOTH");
         Print("UseBollingerFilter: ", UseBollingerFilter ? "YES" : "NO");
         Print("ADX Condition: ", adxCondition ? "YES" : "NO");
         Print("RSI Condition: ", rsiCondition ? "YES" : "NO");
         Print("Spread Condition: ", spreadInPips <= MaxSpread ? "YES" : "NO");
         Print("Time Condition: ", currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes < endTimeInMinutes ? "YES" : "NO");
         Print("AntiDrawdown: ", !UseAntiDrawdown || !ShouldStopTradingDirection(POSITION_TYPE_SELL) ? "YES" : "NO");
         
         // Check if price is below (lower band + 10 pips)
         if(currentBid < lowerBandPlusPips) {
            // Check if we should stop trading Sell based on Anti Drawdown
            if(!UseAntiDrawdown || !ShouldStopTradingDirection(POSITION_TYPE_SELL)) {
               canOpenSell = true;
               Print("=== ENTRY SELL TRIGGERED ===");
               Print("Reason: Price below lower band + min distance");
            }
         }
      }
   }
   
   // Open new trades if conditions are met
   if(canOpenBuy) {
      Print("=== OPENING BUY ORDER ===");
      Print("Current Bid: ", currentBid);
      Print("Upper Band: ", upperBand);
      Print("Upper Band - MinDistance: ", upperBand - (MinDistanceFromBB * _Point * 10));
      OpenBuyOrder();
      lastBidPrice = currentBid;  // Update lastBidPrice only after a trade
      totalPriceMovement = 0;     // Reset total movement
      lastOpenTime = currentTime; // Update last trade time
   }
   if(canOpenSell) {
      Print("=== OPENING SELL ORDER ===");
      Print("Current Bid: ", currentBid);
      Print("Lower Band: ", lowerBand);
      Print("Lower Band + MinDistance: ", lowerBand + (MinDistanceFromBB * _Point * 10));
      OpenSellOrder();
      lastBidPrice = currentBid;  // Update lastBidPrice only after a trade
      totalPriceMovement = 0;     // Reset total movement
      lastOpenTime = currentTime; // Update last trade time
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
   
   // Check if we've reached the maximum number of Buy positions
   if(totalBuyPositions >= MaxBuyPositions) {
      return;
   }
   
   if(totalBuyPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
      
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
               if(trade.Buy(calculatedLots, _Symbol, 0, 0, 0, expertName)) {
                  lastBuyPositionTime = currentTime; // Update time of last Buy position
                  PrintFormat("BUY order opened - Price: %.5f, Lots: %.2f", currentBid, calculatedLots);
               }
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
   
   // Check if we've reached the maximum number of Sell positions
   if(totalSellPositions >= MaxSellPositions) {
      return;
   }
   
   if(totalSellPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
      
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
               if(trade.Sell(calculatedLots, _Symbol, 0, 0, 0, expertName)) {
                  lastSellPositionTime = currentTime; // Update time of last Sell position
                  PrintFormat("SELL order opened - Price: %.5f, Lots: %.2f", currentAsk, calculatedLots);
               }
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
               Print("Minimum distance not met: ", NormalizeDouble(distanceInPips, 1), 
                     " pips < ", minDistancePips, " pips");
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
   
   // Check if we have both positions and total profit is greater than 10
   bool hasBothPositions = buyPositionCount > 0 && sellPositionCount > 0;
   double totalProfit = buyTotalProfit + sellTotalProfit;
   bool shouldStopProfits = hasBothPositions && totalProfit >= 10.0;
   
   // If we have both positions and total profit is greater than 10, close all positions
   if(shouldStopProfits) {
      if(ShowTradeLogs) PrintFormat("Closing all positions - Total profit: %.2f >= 10.0", totalProfit);
      CloseAllPositions();
      return;
   }
   
   // If we have both positions, don't use TP or Trailing
   if(hasBothPositions) {
      return;
   }
   
   // Manage profits and trailing stops only if we don't have both positions
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

   string prefix = "EA_Info_";
   int x = 10;
   int y = 20;
   int yStep = FontSize + 10;
   
   ObjectsDeleteAll(0, prefix);
   
   // Create background rectangle
   CreateRectangle(prefix + "Background", x - 5, y - 5, 300, 600, clrBlack, 200);
   
   // Display EA status
   CreateLabel(prefix + "Title", "=== EA Status ===", x, y, TextColor);
   y += yStep;
   
   // Display current spread with dynamic color
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = spread / (_Point * 10);
   color spreadColor = GetDynamicColor(spreadInPips, MaxSpread, 0);
   CreateLabel(prefix + "Spread", StringFormat("Spread: %.1f pips", spreadInPips), x, y, spreadColor);
   y += yStep;
   
   // Display account information
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = equity - balance;
   double profitPercent = (profit / balance) * 100;
   
   CreateLabel(prefix + "Balance", StringFormat("Balance: %.2f", balance), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "Equity", StringFormat("Equity: %.2f", equity), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "Profit", StringFormat("Profit: %.2f (%.2f%%)", profit, profitPercent), 
              x, y, profit >= 0 ? clrLime : clrRed);
   y += yStep;
   
   // Display Bollinger Bands info with dynamic color
   bollingerBands.Refresh();
   double upperBand = bollingerBands.Upper(0);
   double lowerBand = bollingerBands.Lower(0);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double distanceFromUpper = (currentBid - upperBand) / (_Point * 10);
   double distanceFromLower = (lowerBand - currentBid) / (_Point * 10);
   
   CreateLabel(prefix + "BBFilter", StringFormat("BB Filter: %s", UseBollingerFilter ? "ON" : "OFF"), x, y, TextColor);
   y += yStep;
   
   if(UseBollingerFilter) {
      color bbColor = GetDynamicColor(distanceFromUpper, MinDistanceFromBB, -MinDistanceFromBB);
      CreateLabel(prefix + "BBUpper", StringFormat("BB Upper: %.5f", upperBand), x, y, bbColor);
      y += yStep;
      CreateLabel(prefix + "BBLower", StringFormat("BB Lower: %.5f", lowerBand), x, y, bbColor);
      y += yStep;
      CreateLabel(prefix + "BBStatus", StringFormat("BB Status: %s", 
                 currentBid > upperBand ? "Above Upper" : (currentBid < lowerBand ? "Below Lower" : "Inside Bands")), 
                 x, y, bbColor);
      y += yStep;
   }
   
   // Display ADX info with dynamic color
   if(UseADXFilter) {
      CreateLabel(prefix + "ADXFilter", StringFormat("ADX Filter: %s", UseADXFilter ? "ON" : "OFF"), x, y, TextColor);
      y += yStep;
      
      double adxValue = adxIndicator.Main(0);
      color adxColor = GetDynamicColor(adxValue, MaxADX, MinADX);
      CreateLabel(prefix + "ADXValue", StringFormat("ADX: %.1f (Min: %.1f, Max: %.1f)", 
                 adxValue, MinADX, MaxADX), x, y, adxColor);
      y += yStep;
   }
   
   // Display RSI info with dynamic color
   if(UseRSIFilter) {
      CreateLabel(prefix + "RSIFilter", StringFormat("RSI Filter: %s", UseRSIFilter ? "ON" : "OFF"), x, y, TextColor);
      y += yStep;
      
      double rsiValue = rsiIndicator.Main(0);
      color rsiColor = GetDynamicColor(rsiValue, RSIOverbought, RSIOversold);
      CreateLabel(prefix + "RSIValue", StringFormat("RSI: %.1f (Overbought: %.1f, Oversold: %.1f)", 
                 rsiValue, RSIOverbought, RSIOversold), x, y, rsiColor);
      y += yStep;
   }
   
   // Calculate positions info
   int totalBuyPositions = CountPositions(POSITION_TYPE_BUY);
   int totalSellPositions = CountPositions(POSITION_TYPE_SELL);
   double buyTotalProfit = 0;
   double sellTotalProfit = 0;
   double buyAveragePrice = 0;
   double sellAveragePrice = 0;
   double buyTotalLots = 0;
   double sellTotalLots = 0;
   
   // Calculate profits and averages
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyTotalProfit += PositionGetDouble(POSITION_PROFIT);
               buyAveragePrice += PositionGetDouble(POSITION_PRICE_OPEN) * positionLots;
               buyTotalLots += positionLots;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellTotalProfit += PositionGetDouble(POSITION_PROFIT);
               sellAveragePrice += PositionGetDouble(POSITION_PRICE_OPEN) * positionLots;
               sellTotalLots += positionLots;
            }
         }
      }
   }
   
   // Calculate average prices
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   // Calculate drawdowns
   double currentBuyDD = 0;
   double currentSellDD = 0;
   
   if(buyTotalProfit < 0) {
      currentBuyDD = MathAbs(buyTotalProfit) / initialBalance * 100;
      maxBuyDD = MathMax(maxBuyDD, currentBuyDD);
   }
   
   if(sellTotalProfit < 0) {
      currentSellDD = MathAbs(sellTotalProfit) / initialBalance * 100;
      maxSellDD = MathMax(maxSellDD, currentSellDD);
   }
   
   // Calculate total drawdown
   double totalProfit = buyTotalProfit + sellTotalProfit;
   double currentTotalDD = 0;
   
   if(totalProfit < 0) {
      currentTotalDD = MathAbs(totalProfit) / initialBalance * 100;
      maxTotalDD = MathMax(maxTotalDD, currentTotalDD);
   }
   
   // Display Buy information
   CreateLabel(prefix + "BuyPositions", StringFormat("Buy Positions: %d (%.2f lots)", totalBuyPositions, buyTotalLots), x, y, clrLime);
   y += yStep;
   if(totalBuyPositions > 0) {
      CreateLabel(prefix + "BuyProfit", StringFormat("Buy Profit: %.2f", buyTotalProfit), x, y, clrLime);
      y += yStep;
      CreateLabel(prefix + "BuyAverage", StringFormat("Buy Avg Price: %.5f", buyAveragePrice), x, y, clrLime);
      y += yStep;
      CreateLabel(prefix + "BuyDD", StringFormat("Buy DD: %.2f%% (Max: %.2f%%)", currentBuyDD, maxBuyDD), x, y, 
                 currentBuyDD > 0 ? clrOrange : clrLime);
      y += yStep;
   }
   
   // Display Sell information
   CreateLabel(prefix + "SellPositions", StringFormat("Sell Positions: %d (%.2f lots)", totalSellPositions, sellTotalLots), x, y, clrRed);
   y += yStep;
   if(totalSellPositions > 0) {
      CreateLabel(prefix + "SellProfit", StringFormat("Sell Profit: %.2f", sellTotalProfit), x, y, clrRed);
      y += yStep;
      CreateLabel(prefix + "SellAverage", StringFormat("Sell Avg Price: %.5f", sellAveragePrice), x, y, clrRed);
      y += yStep;
      CreateLabel(prefix + "SellDD", StringFormat("Sell DD: %.2f%% (Max: %.2f%%)", currentSellDD, maxSellDD), x, y, 
                 currentSellDD > 0 ? clrOrange : clrRed);
      y += yStep;
   }
   
   // Display total information
   y += yStep;
   int totalPositions = totalBuyPositions + totalSellPositions;
   double totalLots = buyTotalLots + sellTotalLots;
   CreateLabel(prefix + "TotalPositions", StringFormat("Total Positions: %d (%.2f lots)", totalPositions, totalLots), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "TotalProfit", StringFormat("Total Profit: %.2f", totalProfit), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "TotalDD", StringFormat("Total DD: %.2f%% (Max: %.2f%%)", currentTotalDD, maxTotalDD), x, y, 
              currentTotalDD > 0 ? clrOrange : TextColor);
   y += yStep;
   
   // Display next trade time
   datetime currentTime = TimeCurrent();
   if(lastOpenTime > 0) {
      datetime nextOpenTime = lastOpenTime + 60;
      if(nextOpenTime > currentTime) {
         CreateLabel(prefix + "NextTrade", StringFormat("Next Trade: %s", 
                    TimeToString(nextOpenTime, TIME_MINUTES|TIME_SECONDS)), x, y, TextColor);
      }
   }
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
//| Check if we have both Buy and Sell positions open                 |
//+------------------------------------------------------------------+
bool HasBothPositionsOpen() {
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   return buyCount > 0 && sellCount > 0;
}

//+------------------------------------------------------------------+
//| Check if we should stop trading in a direction                    |
//+------------------------------------------------------------------+
bool ShouldStopTradingDirection(ENUM_POSITION_TYPE positionType) {
   if(!HasBothPositionsOpen()) return false;
   
   // Calculate total profit and weighted lot profit
   double totalProfit = 0;
   double totalLots = 0;
   double weightedProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            totalProfit += positionProfit;
            totalLots += positionLots;
            weightedProfit += positionProfit / positionLots;
         }
      }
   }
   
   // Calculate average profit per weighted lot
   double avgProfitPerLot = totalLots > 0 ? weightedProfit / totalLots : 0;
   
   // Check conditions based on selected method
   if(UseWeightedLotProfit) {
      // Use profit per weighted lot
      if(avgProfitPerLot >= MinProfitPerWeightedLot) {
         CloseAllPositions();
         return true;
      }
   } else {
      // Use fixed currency amount
      if(totalProfit >= MinTotalProfitToAvoidDD) {
         CloseAllPositions();
         return true;
      }
   }
   
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
   PrintFormat("Bid: %.5f | BuyLine: %.5f | SellLine: %.5f | Buy: %d(%.2f/%.2f) | Sell: %d(%.2f/%.2f) | Spread: %.1f | ADX: %.1f | RSI: %.1f",
         currentBid, buyLine, sellLine, 
         buyPositions, buyProfit, buyLots,
         sellPositions, sellProfit, sellLots,
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
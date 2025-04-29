//+------------------------------------------------------------------+
//|                                                      ProfitableGbpUsd.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\TerminalInfo.mqh>

// Enumerations
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY = 0,    // Trading Buy only
   TRADE_SELL = 1,   // Trading Sell only
   TRADE_BOTH = 2    // Trading both directions
};

// Input parameters
input group "=== GENERAL SETTINGS ==="
input int      Magic = 254689;         // Magic Number
input string   Comments = "1pair1trade1day";  // Comments
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Trade Direction
input int      MaxSpread = 40;         // Max Spread Allowed (in points)
input int      Slippage = 3;           // Slippage (in points)

input group "=== RISK MANAGEMENT ==="
input double   FixedLot = 0.01;        // Fixed Lot
input bool     EnableRiskPercent = true;  // Enable Risk Percent
input double   RiskPercent = 1.0;      // Risk Percent
input int      MaxDailyBuyTrades = 5;  // Maximum Daily Buy Trades
input int      MaxDailySellTrades = 5; // Maximum Daily Sell Trades

input group "=== TAKE PROFIT & STOP LOSS ==="
input int      TakeProfit = 1000;       // Take Profit (in points)
input int      StopLoss = 5000;         // Stop Loss (in points)

input group "=== BREAKEVEN SETTINGS ==="
input bool     EnableBreakEven = true;  // Enable BreakEven
input int      BreakEvenStart = 100;    // BreakEven Start (in points)
input int      BreakEvenLevel = 80;     // BreakEven Level (in points)

input group "=== TRAILING STOP LOSS ==="
input bool     EnableTrailingStop = true;  // Enable Trailing Stop Loss
input int      TrailingStopStart = 500;  // Trailing Stop Loss Start (in points)
input int      TrailingStopLevel = 300;  // Trailing Stop Loss Level (in points)
input bool     Stealth = false;         // Stealth (Hide TP and SL)

input group "=== STRATEGY ==="
input int      BufferDistance = 90;     // Buffer Distance (in points)
input int      BuyStopOrders = 5;       // Quantity of Buy Stop Orders
input int      SellStopOrders = 5;      // Quantity of Sell Stop Orders
input int      CloseOrdersHour = 20;    // Close Pending Orders Hour
input int      CloseOrdersMinute = 0;   // Close Pending Orders Minute
input int      MaxBuyEntries = 25;      // Max Open Buy Entries
input int      MaxSellEntries = 25;     // Max Open Sell Entries
input int      MaxTotalEntries = 25;    // Max Total Open Entries
input group "=== HIGH/LOW CALCULATION ==="
input ENUM_TIMEFRAMES HighLowTimeframe = PERIOD_CURRENT;  // Timeframe for High/Low calculation
input bool     ShowHighLowLine = true;  // Show Daily High and Low lines
input color    HighLineColor = clrForestGreen; // Daily High Color
input color    LowLineColor = clrRed;   // Daily Low Color
input int      HighLowStartHour = 3;    // Daily High And Low Start Hour (0-23)
input int      HighLowStartMinute = 0;  // Daily High And Low Start Minute (0-59)
input int      HighLowEndHour = 11;      // Daily High And Low End Hour (0-23)
input int      HighLowEndMinute = 0;    // Daily High And Low End Minute (0-59)

// Global variables
CTrade trade;
datetime lastHighLowUpdate = 0;
double dailyHigh = 0;
double dailyLow = 0;
bool highLowCalculated = false;
bool ordersPlaced = false;
bool isConnected = false;
bool isSynchronized = false;
datetime lastSyncTime = 0;
int syncRetryCount = 0;
const int MAX_SYNC_RETRIES = 3;

// Cache variables
datetime lastPositionCountTime = 0;
int cachedTotalPositions = 0;
datetime lastSpreadCheckTime = 0;
int cachedSpread = 0;

// Panel variables
string panelName = "TradingPanel";
int panelWidth = 200;
int panelHeight = 300;
int panelX = 10;
int panelY = 20;
int lineHeight = 20;
int fontSize = 8;
color panelBackground = clrWhite;
color panelBorder = clrBlack;
color textColor = clrBlack;
color profitColor = clrForestGreen;
color lossColor = clrRed;
color warningColor = clrOrange;
color normalColor = clrBlack;

// Performance tracking variables
double maxEquity = 0;
double minEquity = 0;
double totalProfit = 0;
double totalLots = 0;
double maxDrawdown = 0;

// Daily trade counters
int dailyBuyTrades = 0;
int dailySellTrades = 0;
datetime lastTradeDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   // Validate input parameters
   if(MaxSpread <= 0) {
      Print("Error: MaxSpread must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(Slippage < 0) {
      Print("Error: Slippage cannot be negative");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(FixedLot <= 0) {
      Print("Error: FixedLot must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(EnableRiskPercent && RiskPercent <= 0) {
      Print("Error: RiskPercent must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(TakeProfit <= 0) {
      Print("Error: TakeProfit must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(StopLoss <= 0) {
      Print("Error: StopLoss must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(EnableBreakEven) {
      if(BreakEvenStart <= 0) {
         Print("Error: BreakEvenStart must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(BreakEvenLevel <= 0) {
         Print("Error: BreakEvenLevel must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
   }
   
   if(EnableTrailingStop) {
      if(TrailingStopStart <= 0) {
         Print("Error: TrailingStopStart must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
      if(TrailingStopLevel <= 0) {
         Print("Error: TrailingStopLevel must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
   }
   
   if(BufferDistance <= 0) {
      Print("Error: BufferDistance must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(BuyStopOrders <= 0) {
      Print("Error: BuyStopOrders must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(SellStopOrders <= 0) {
      Print("Error: SellStopOrders must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxBuyEntries <= 0) {
      Print("Error: MaxBuyEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxSellEntries <= 0) {
      Print("Error: MaxSellEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxTotalEntries <= 0) {
      Print("Error: MaxTotalEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(HighLowStartHour < 0 || HighLowStartHour > 23) {
      Print("Error: HighLowStartHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(HighLowStartMinute < 0 || HighLowStartMinute > 59) {
      Print("Error: HighLowStartMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(HighLowEndHour < 0 || HighLowEndHour > 23) {
      Print("Error: HighLowEndHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(HighLowEndMinute < 0 || HighLowEndMinute > 59) {
      Print("Error: HighLowEndMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(CloseOrdersHour < 0 || CloseOrdersHour > 23) {
      Print("Error: CloseOrdersHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(CloseOrdersMinute < 0 || CloseOrdersMinute > 59) {
      Print("Error: CloseOrdersMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxDailyBuyTrades <= 0) {
      Print("Error: MaxDailyBuyTrades must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(MaxDailySellTrades <= 0) {
      Print("Error: MaxDailySellTrades must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Check if High/Low calculation period is valid
   int startMinutes = HighLowStartHour * 60 + HighLowStartMinute;
   int endMinutes = HighLowEndHour * 60 + HighLowEndMinute;
   if(startMinutes >= endMinutes) {
      Print("Error: High/Low calculation period is invalid (start time must be before end time)");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   // Check connection
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
      Print("No connection to the server!");
      return INIT_FAILED;
   }
   
   // Check if symbol is GBPUSD
   if(Symbol() != "GBPUSD") {
      Print("This EA is designed for GBPUSD only!");
      return INIT_FAILED;
   }
   
   // Check synchronization
   if(!IsSynchronized()) {
      Print("Failed to synchronize with the server!");
      return INIT_FAILED;
   }
   
   CreateTradingPanel();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check if terminal is synchronized with server                      |
//+------------------------------------------------------------------+
bool IsSynchronized() {
   if(TerminalInfoInteger(TERMINAL_CONNECTED)) {
      isSynchronized = true;
      lastSyncTime = TimeCurrent();
      syncRetryCount = 0;
      return true;
   }
   
   if(syncRetryCount < MAX_SYNC_RETRIES) {
      syncRetryCount++;
      Print("Waiting for synchronization... Attempt ", syncRetryCount, " of ", MAX_SYNC_RETRIES);
      return false;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Delete graphical objects
   ObjectDelete(0, "DailyHigh");
   ObjectDelete(0, "DailyLow");
   
   DeleteTradingPanel();
}

//+------------------------------------------------------------------+
//| Get cached total positions count                                   |
//+------------------------------------------------------------------+
int GetCachedTotalPositions() {
   if(TimeCurrent() - lastPositionCountTime > 1) { // Update cache every second
      cachedTotalPositions = CountTotalOpenPositions();
      lastPositionCountTime = TimeCurrent();
   }
   return cachedTotalPositions;
}

//+------------------------------------------------------------------+
//| Get cached spread                                                  |
//+------------------------------------------------------------------+
int GetCachedSpread() {
   if(TimeCurrent() - lastSpreadCheckTime > 1) { // Update cache every second
      cachedSpread = (int)SymbolInfoInteger("GBPUSD", SYMBOL_SPREAD);
      lastSpreadCheckTime = TimeCurrent();
   }
   return cachedSpread;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Check connection
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
      isConnected = false;
      Print("Connection lost!");
      return;
   }
   
   if(!isConnected) {
      isConnected = true;
      Print("Connection restored!");
   }
   
   // Check synchronization periodically
   if(TimeCurrent() - lastSyncTime > 60) {
      isSynchronized = IsSynchronized();
   }
   
   if(!isSynchronized) {
      return;
   }
   
   // Check spread using cache
   if(GetCachedSpread() > MaxSpread) {
      return;
   }
   
   // Check and update daily highs and lows
   UpdateDailyHighLow();
   
   // Place pending orders at 11:00
   PlacePendingOrders();
   
   // Manage pending orders
   ManagePendingOrders();
   
   // Manage open positions
   ManageOpenPositions();
   
   UpdateTradingPanel();
}

//+------------------------------------------------------------------+
//| Update daily high and low                                          |
//+------------------------------------------------------------------+
void UpdateDailyHighLow() {
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   // Check if we are in the calculation period
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int startMinutes = HighLowStartHour * 60 + HighLowStartMinute;
   int endMinutes = HighLowEndHour * 60 + HighLowEndMinute;
   int closeMinutes = CloseOrdersHour * 60 + CloseOrdersMinute;
   
   // Reset at the start of the calculation period
   if(currentMinutes == startMinutes) {
      highLowCalculated = false;
      dailyHigh = 0;
      dailyLow = 0;
      ObjectDelete(0, "DailyHigh");
      ObjectDelete(0, "DailyLow");
      Print("Resetting High/Low calculation at ", TimeToString(TimeCurrent()));
   }
   
   // Calculate High/Low during the specified period
   if(currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
      if(!highLowCalculated) {
         CalculateDailyHighLow();
         highLowCalculated = true;
      } else {
         // Get current bar data
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         if(CopyRates("GBPUSD", HighLowTimeframe, 0, 1, rates) > 0) {
            // Update daily high/low if needed
            if(rates[0].high > dailyHigh) {
               dailyHigh = rates[0].high;
               Print("New High found: ", dailyHigh, " at ", TimeToString(rates[0].time));
            }
            if(rates[0].low < dailyLow) {
               dailyLow = rates[0].low;
               Print("New Low found: ", dailyLow, " at ", TimeToString(rates[0].time));
            }
            
            // Update line positions
            if(ShowHighLowLine) {
               // Delete existing lines
               ObjectDelete(0, "DailyHigh");
               ObjectDelete(0, "DailyLow");
               
               // Get start and end times for the current day
               MqlDateTime startTime;
               TimeToStruct(TimeCurrent(), startTime);
               startTime.hour = HighLowStartHour;
               startTime.min = HighLowStartMinute;
               startTime.sec = 0;
               datetime start = StructToTime(startTime);
               
               MqlDateTime endTime;
               TimeToStruct(TimeCurrent(), endTime);
               endTime.hour = HighLowEndHour;
               endTime.min = HighLowEndMinute;
               endTime.sec = 0;
               datetime end = StructToTime(endTime);
               
               // Create High line segment
               ObjectCreate(0, "DailyHigh", OBJ_TREND, 0, start, dailyHigh, end, dailyHigh);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_COLOR, HighLineColor);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_WIDTH, 2);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_BACK, false);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_SELECTABLE, true);
               ObjectSetInteger(0, "DailyHigh", OBJPROP_HIDDEN, false);
               ObjectSetString(0, "DailyHigh", OBJPROP_TEXT, "Daily High");
               
               // Create Low line segment
               ObjectCreate(0, "DailyLow", OBJ_TREND, 0, start, dailyLow, end, dailyLow);
               ObjectSetInteger(0, "DailyLow", OBJPROP_COLOR, LowLineColor);
               ObjectSetInteger(0, "DailyLow", OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, "DailyLow", OBJPROP_WIDTH, 2);
               ObjectSetInteger(0, "DailyLow", OBJPROP_BACK, false);
               ObjectSetInteger(0, "DailyLow", OBJPROP_SELECTABLE, true);
               ObjectSetInteger(0, "DailyLow", OBJPROP_HIDDEN, false);
               ObjectSetString(0, "DailyLow", OBJPROP_TEXT, "Daily Low");
            }
         }
      }
   }
   // Delete lines at close time
   else if(currentMinutes == closeMinutes) {
      highLowCalculated = false;
      ObjectDelete(0, "DailyHigh");
      ObjectDelete(0, "DailyLow");
      Print("Deleting High/Low lines at close time: ", TimeToString(TimeCurrent()));
   }
}

//+------------------------------------------------------------------+
//| Calculate daily high and low                                       |
//+------------------------------------------------------------------+
void CalculateDailyHighLow() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Get data from the start of the period
   MqlDateTime startTime;
   TimeToStruct(TimeCurrent(), startTime);
   startTime.hour = HighLowStartHour;
   startTime.min = HighLowStartMinute;
   startTime.sec = 0;
   datetime start = StructToTime(startTime);
   
   MqlDateTime endTime;
   TimeToStruct(TimeCurrent(), endTime);
   endTime.hour = HighLowEndHour;
   endTime.min = HighLowEndMinute;
   endTime.sec = 0;
   datetime end = StructToTime(endTime);
   
   // Use the selected timeframe for calculation
   if(CopyRates("GBPUSD", HighLowTimeframe, start, end, rates) > 0) {
      // Initialize with first bar values
      dailyHigh = rates[0].high;
      dailyLow = rates[0].low;
      
      Print("Starting High/Low calculation from ", TimeToString(start), " to ", TimeToString(end));
      Print("First bar - High: ", rates[0].high, " Low: ", rates[0].low, " Open: ", rates[0].open, " Close: ", rates[0].close, " Time: ", TimeToString(rates[0].time));
      
      // Find true high and low including wicks
      for(int i = 1; i < ArraySize(rates); i++) {
         if(rates[i].high > dailyHigh) {
            dailyHigh = rates[i].high;
            Print("New High found at ", TimeToString(rates[i].time), ": ", dailyHigh, " (Bar High: ", rates[i].high, " Open: ", rates[i].open, " Close: ", rates[i].close, ")");
         }
         if(rates[i].low < dailyLow) {
            dailyLow = rates[i].low;
            Print("New Low found at ", TimeToString(rates[i].time), ": ", dailyLow, " (Bar Low: ", rates[i].low, " Open: ", rates[i].open, " Close: ", rates[i].close, ")");
         }
      }
      
      Print("Final Daily High: ", dailyHigh, " Low: ", dailyLow);
      
      // Draw lines if enabled
      if(ShowHighLowLine) {
         // Delete existing lines first
         ObjectDelete(0, "DailyHigh");
         ObjectDelete(0, "DailyLow");
         
         // Create High line segment
         ObjectCreate(0, "DailyHigh", OBJ_TREND, 0, start, dailyHigh, end, dailyHigh);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_COLOR, HighLineColor);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_BACK, false);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, "DailyHigh", OBJPROP_HIDDEN, false);
         ObjectSetString(0, "DailyHigh", OBJPROP_TEXT, "Daily High");
         
         // Create Low line segment
         ObjectCreate(0, "DailyLow", OBJ_TREND, 0, start, dailyLow, end, dailyLow);
         ObjectSetInteger(0, "DailyLow", OBJPROP_COLOR, LowLineColor);
         ObjectSetInteger(0, "DailyLow", OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, "DailyLow", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "DailyLow", OBJPROP_BACK, false);
         ObjectSetInteger(0, "DailyLow", OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, "DailyLow", OBJPROP_HIDDEN, false);
         ObjectSetString(0, "DailyLow", OBJPROP_TEXT, "Daily Low");
         
         Print("High/Low lines drawn from ", TimeToString(start), " to ", TimeToString(end));
      }
   } else {
      Print("Failed to copy rates for High/Low calculation. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Count total open positions                                         |
//+------------------------------------------------------------------+
int CountTotalOpenPositions() {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == "GBPUSD" && 
            PositionGetInteger(POSITION_MAGIC) == Magic) {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Place pending orders                                               |
//+------------------------------------------------------------------+
void PlacePendingOrders() {
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   // Reset daily trade counters and ordersPlaced flag at midnight
   if(lastTradeDate != currentTime.day) {
      dailyBuyTrades = 0;
      dailySellTrades = 0;
      ordersPlaced = false;  // Reset the flag at midnight
      lastTradeDate = currentTime.day;
   }
   
   // Check if it's time to place orders
   if(currentTime.hour == HighLowEndHour && currentTime.min == HighLowEndMinute && !ordersPlaced) {
      // Delete existing orders
      DeleteAllPendingOrders();
      
      // Check total open positions using cache
      int totalPositions = GetCachedTotalPositions();
      if(totalPositions >= MaxTotalEntries) {
         Print("Maximum total entries reached: ", totalPositions);
         return;
      }
      
      // Calculate prices for Buy Stop orders
      if(TradeDirection == TRADE_BUY || TradeDirection == TRADE_BOTH) {
         if(dailyBuyTrades >= MaxDailyBuyTrades) {
            Print("Maximum daily buy trades reached: ", dailyBuyTrades);
            return;
         }
         
         double buyStopPrice = dailyHigh + BufferDistance * Point();
         double lotSize = CalculateLotSize();
         int buyPositions = CountOpenPositions(ORDER_TYPE_BUY);
         
         for(int i = 0; i < BuyStopOrders; i++) {
            if(buyPositions < MaxBuyEntries && totalPositions < MaxTotalEntries) {
               double tp = Stealth ? 0 : buyStopPrice + TakeProfit * Point();
               double sl = Stealth ? 0 : buyStopPrice - StopLoss * Point();
               
               if(!trade.BuyStop(lotSize, buyStopPrice, "GBPUSD", sl, tp, 
                               ORDER_TIME_SPECIFIED, TimeCurrent() + 9 * 3600, Comments)) {
                  Print("Failed to place Buy Stop order. Error: ", GetLastError());
               } else {
                  dailyBuyTrades++;
               }
               buyPositions++;
               totalPositions++;
            }
         }
      }
      
      // Calculate prices for Sell Stop orders
      if(TradeDirection == TRADE_SELL || TradeDirection == TRADE_BOTH) {
         if(dailySellTrades >= MaxDailySellTrades) {
            Print("Maximum daily sell trades reached: ", dailySellTrades);
            return;
         }
         
         double sellStopPrice = dailyLow - BufferDistance * Point();
         double lotSize = CalculateLotSize();
         int sellPositions = CountOpenPositions(ORDER_TYPE_SELL);
         
         for(int i = 0; i < SellStopOrders; i++) {
            if(sellPositions < MaxSellEntries && totalPositions < MaxTotalEntries) {
               double tp = Stealth ? 0 : sellStopPrice - TakeProfit * Point();
               double sl = Stealth ? 0 : sellStopPrice + StopLoss * Point();
               
               if(!trade.SellStop(lotSize, sellStopPrice, "GBPUSD", sl, tp, 
                                ORDER_TIME_SPECIFIED, TimeCurrent() + 9 * 3600, Comments)) {
                  Print("Failed to place Sell Stop order. Error: ", GetLastError());
               } else {
                  dailySellTrades++;
               }
               sellPositions++;
               totalPositions++;
            }
         }
      }
      
      ordersPlaced = true;
      Print("Orders placed successfully. Total positions: ", totalPositions);
   }
   
   // Reset flag at midnight
   if(currentTime.hour == 0 && currentTime.min == 0) {
      ordersPlaced = false;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk settings                          |
//+------------------------------------------------------------------+
double CalculateLotSize() {
   if(EnableRiskPercent) {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = accountBalance * RiskPercent / 100.0;
      double tickValue = SymbolInfoDouble("GBPUSD", SYMBOL_TRADE_TICK_VALUE);
      double lotStep = SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_STEP);
      
      double lots = NormalizeDouble(riskAmount / (StopLoss * tickValue), 2);
      lots = MathFloor(lots / lotStep) * lotStep;
      
      return MathMin(lots, SymbolInfoDouble("GBPUSD", SYMBOL_VOLUME_MAX));
   }
   
   return FixedLot;
}

//+------------------------------------------------------------------+
//| Count open positions of specific type                              |
//+------------------------------------------------------------------+
int CountOpenPositions(ENUM_ORDER_TYPE type) {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == "GBPUSD" && 
            PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetInteger(POSITION_TYPE) == type) {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                          |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders(ENUM_ORDER_TYPE orderType = WRONG_VALUE) {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0) {
         if(OrderGetString(ORDER_SYMBOL) == "GBPUSD" && 
            OrderGetInteger(ORDER_MAGIC) == Magic) {
            if(orderType == WRONG_VALUE || OrderGetInteger(ORDER_TYPE) == orderType) {
               if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP || 
                  OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                  trade.OrderDelete(ticket);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                              |
//+------------------------------------------------------------------+
void ManageOpenPositions() {
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetString(POSITION_SYMBOL) == "GBPUSD" && 
            PositionGetInteger(POSITION_MAGIC) == Magic) {
            
            ulong ticket = PositionGetTicket(i);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Manage BreakEven
            if(EnableBreakEven) {
               double profitInPoints = 0;
               if(posType == POSITION_TYPE_BUY) {
                  profitInPoints = (currentPrice - openPrice) / Point();
               } else {
                  profitInPoints = (openPrice - currentPrice) / Point();
               }
               
               // Check if we should activate BreakEven
               if(profitInPoints >= BreakEvenStart) {
                  double newSL = 0;
                  
                  // Calculate BreakEven level based on position type
                  if(posType == POSITION_TYPE_BUY) {
                     newSL = openPrice + BreakEvenLevel * Point();
                  } else {
                     newSL = openPrice - BreakEvenLevel * Point();
                  }
                  
                  // Only modify if the new SL is more favorable than current SL
                  if((posType == POSITION_TYPE_BUY && newSL > sl) || 
                     (posType == POSITION_TYPE_SELL && (newSL < sl || sl == 0))) {
                     if(!trade.PositionModify(ticket, newSL, tp)) {
                        Print("Failed to modify position for BreakEven. Error: ", GetLastError());
                     } else {
                        Print("BreakEven activated - Old SL: ", sl, " New SL: ", newSL, " Profit in points: ", profitInPoints);
                     }
                  }
               }
            }
            
            // Manage Trailing Stop
            if(EnableTrailingStop) {
               double profitInPoints = 0;
               if(posType == POSITION_TYPE_BUY) {
                  profitInPoints = (currentPrice - openPrice) / Point();
               } else {
                  profitInPoints = (openPrice - currentPrice) / Point();
               }
               
               // Trailing Stop activates when profit reaches TrailingStopStart
               if(profitInPoints >= TrailingStopStart) {
                  double newSL = 0;
                  
                  if(posType == POSITION_TYPE_BUY) {
                     // Calculate new SL based on current price
                     newSL = currentPrice - TrailingStopLevel * Point();
                     // Only move SL if it's more favorable than current SL
                     if(newSL > sl) {
                        if(!trade.PositionModify(ticket, newSL, tp)) {
                           Print("Failed to modify position for Trailing Stop. Error: ", GetLastError());
                        } else {
                           Print("Trailing Stop updated - Old SL: ", sl, " New SL: ", newSL, " Current Price: ", currentPrice);
                        }
                     }
                  } else {
                     // Calculate new SL based on current price
                     newSL = currentPrice + TrailingStopLevel * Point();
                     // Only move SL if it's more favorable than current SL
                     if(newSL < sl || sl == 0) {
                        if(!trade.PositionModify(ticket, newSL, tp)) {
                           Print("Failed to modify position for Trailing Stop. Error: ", GetLastError());
                        } else {
                           Print("Trailing Stop updated - Old SL: ", sl, " New SL: ", newSL, " Current Price: ", currentPrice);
                        }
                     }
                  }
               }
            }
            
            // Close opposite orders if an order is triggered
            if(posType == POSITION_TYPE_BUY) {
               DeleteAllPendingOrders(ORDER_TYPE_SELL_STOP);
            } else if(posType == POSITION_TYPE_SELL) {
               DeleteAllPendingOrders(ORDER_TYPE_BUY_STOP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage pending orders                                              |
//+------------------------------------------------------------------+
void ManagePendingOrders() {
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   // Check if we are at or past closing time
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int closeMinutes = CloseOrdersHour * 60 + CloseOrdersMinute;
   
   if(currentMinutes >= closeMinutes) {
      // Check if we have already closed orders today
      static datetime lastCloseDate = 0;
      datetime currentDate = TimeCurrent() - (TimeCurrent() % 86400); // Current date at midnight
      
      if(lastCloseDate != currentDate) {
         // Delete all pending orders
         int ordersDeleted = 0;
         for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if(ticket > 0) {
               if(OrderGetString(ORDER_SYMBOL) == "GBPUSD" && 
                  OrderGetInteger(ORDER_MAGIC) == Magic) {
                  if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP || 
                     OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                     if(trade.OrderDelete(ticket)) {
                        ordersDeleted++;
                     } else {
                        Print("Failed to delete pending order. Error: ", GetLastError());
                     }
                  }
               }
            }
         }
         
         if(ordersDeleted > 0) {
            Print("Closed ", ordersDeleted, " pending orders at ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
         }
         
         lastCloseDate = currentDate;
      }
   }
}

//+------------------------------------------------------------------+
//| Create Trading Panel                                              |
//+------------------------------------------------------------------+
void CreateTradingPanel() {
   // Create panel background
   ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, panelX);
   ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, panelY);
   ObjectSetInteger(0, panelName, OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, panelName, OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, panelBackground);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_COLOR, panelBorder);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, panelName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, panelName, OBJPROP_ZORDER, 0);
   
   // Panel title
   ObjectCreate(0, panelName + "_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, panelName + "_Title", OBJPROP_TEXT, "Trading Panel");
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_XDISTANCE, panelX + 5);
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_YDISTANCE, panelY + 5);
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_FONTSIZE, fontSize + 2);
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, panelName + "_Title", OBJPROP_HIDDEN, true);
   
   UpdateTradingPanel();
}

//+------------------------------------------------------------------+
//| Update Trading Panel                                              |
//+------------------------------------------------------------------+
void UpdateTradingPanel() {
   int yOffset = panelY + 30;
   int line = 0;
   
   // Account information
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   // Update performance
   if(equity > maxEquity) {
      maxEquity = equity;
      minEquity = equity; // Reset minimum when reaching new maximum
   }
   if(equity < minEquity) minEquity = equity;
   
   // Calculate current and maximum drawdown
   double currentDrawdown = (maxEquity - minEquity) / maxEquity * 100;
   if(currentDrawdown > maxDrawdown) maxDrawdown = currentDrawdown;
   
   // Calculate total profit and lots
   totalProfit = equity - balance;
   totalLots = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0) {
         if(PositionGetString(POSITION_SYMBOL) == "GBPUSD" && 
            PositionGetInteger(POSITION_MAGIC) == Magic) {
            totalLots += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   
   // Current spread
   int spread = (int)SymbolInfoInteger("GBPUSD", SYMBOL_SPREAD);
   color spreadColor = spread <= MaxSpread ? normalColor : warningColor;
   
   // Update information
   UpdatePanelLine("Balance: " + DoubleToString(balance, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Equity: " + DoubleToString(equity, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Profit: " + DoubleToString(profit, 2), line++, yOffset, profit >= 0 ? profitColor : lossColor);
   UpdatePanelLine("Total Profit: " + DoubleToString(totalProfit, 2), line++, yOffset, totalProfit >= 0 ? profitColor : lossColor);
   UpdatePanelLine("Current Drawdown: " + DoubleToString(currentDrawdown, 2) + "%", line++, yOffset, currentDrawdown > 10 ? warningColor : normalColor);
   UpdatePanelLine("Max Drawdown: " + DoubleToString(maxDrawdown, 2) + "%", line++, yOffset, maxDrawdown > 10 ? warningColor : normalColor);
   UpdatePanelLine("Margin: " + DoubleToString(margin, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Free Margin: " + DoubleToString(freeMargin, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Margin Level: " + DoubleToString(marginLevel, 2) + "%", line++, yOffset, 
                  marginLevel > 100 ? normalColor : warningColor);
   
   // Trading information
   UpdatePanelLine("--- Trading Info ---", line++, yOffset, textColor);
   UpdatePanelLine("Spread: " + IntegerToString(spread), line++, yOffset, spreadColor);
   UpdatePanelLine("Daily High: " + DoubleToString(dailyHigh, 5), line++, yOffset, HighLineColor);
   UpdatePanelLine("Daily Low: " + DoubleToString(dailyLow, 5), line++, yOffset, LowLineColor);
   
   // Open positions
   int totalPositions = CountTotalOpenPositions();
   int buyPositions = CountOpenPositions(ORDER_TYPE_BUY);
   int sellPositions = CountOpenPositions(ORDER_TYPE_SELL);
   
   UpdatePanelLine("--- Positions ---", line++, yOffset, textColor);
   UpdatePanelLine("Total: " + IntegerToString(totalPositions), line++, yOffset, normalColor);
   UpdatePanelLine("Buy: " + IntegerToString(buyPositions), line++, yOffset, profitColor);
   UpdatePanelLine("Sell: " + IntegerToString(sellPositions), line++, yOffset, lossColor);
   UpdatePanelLine("Total Lots: " + DoubleToString(totalLots, 2), line++, yOffset, normalColor);
   
   // Pending orders
   int pendingOrders = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0) {
         if(OrderGetString(ORDER_SYMBOL) == "GBPUSD" && 
            OrderGetInteger(ORDER_MAGIC) == Magic) {
            if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP || 
               OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
               pendingOrders++;
            }
         }
      }
   }
   
   UpdatePanelLine("Pending Orders: " + IntegerToString(pendingOrders), line++, yOffset, normalColor);
   
   // Update panel height
   panelHeight = (line + 1) * lineHeight + 40;
   ObjectSetInteger(0, panelName, OBJPROP_YSIZE, panelHeight);
}

//+------------------------------------------------------------------+
//| Update Panel Line                                                 |
//+------------------------------------------------------------------+
void UpdatePanelLine(string text, int line, int yOffset, color lineColor) {
   string lineName = panelName + "_Line" + IntegerToString(line);
   
   if(ObjectFind(0, lineName) < 0) {
      ObjectCreate(0, lineName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, lineName, OBJPROP_XDISTANCE, panelX + 5);
      ObjectSetInteger(0, lineName, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
   }
   
   ObjectSetString(0, lineName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, lineName, OBJPROP_YDISTANCE, yOffset + line * lineHeight);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
}

//+------------------------------------------------------------------+
//| Delete Trading Panel                                              |
//+------------------------------------------------------------------+
void DeleteTradingPanel() {
   ObjectsDeleteAll(0, panelName);
} 
//+------------------------------------------------------------------+
//|                                                      ProfitableGbpUsd.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link "https://www.mql5.com"
#property version "1.00"
#property strict

// Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\TerminalInfo.mqh>

// Enumerations
enum ENUM_TRADE_DIRECTION
{
   TRADE_BUY = 0,  // Trading Buy only
   TRADE_SELL = 1, // Trading Sell only
   TRADE_BOTH = 2  // Trading both directions
};

// Input parameters
input group "=== TRADING SETTINGS ===" input int Magic = 254689; // Magic Number
input string Comments = "1pair1trade1day";                       // Comments
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;          // Trade Direction
input int MaxSpread = 40;                                        // Max Spread (points)
input int Slippage = 3;                                          // Slippage (points)

input group "=== POSITION MANAGEMENT ===" input int MaxBuyEntries = 25; // Max Buy Entries
input int MaxSellEntries = 25;                                          // Max Sell Entries
input int MaxTotalEntries = 25;                                         // Max Total Entries
input int MaxDailyBuyTrades = 5;                                        // Max Daily Buy Trades
input int MaxDailySellTrades = 5;                                       // Max Daily Sell Trades
input bool DeleteOppositePendingOrders = false;                         // Delete opposite pending orders
input int BuyStopOrders = 5;                                            // Buy Stop Orders Qty
input int SellStopOrders = 5;                                           // Sell Stop Orders Qty
input int CloseOrdersHour = 20;                                         // Close Orders Hour
input int CloseOrdersMinute = 0;                                        // Close Orders Minute

input group "=== RISK MANAGEMENT ===" input double FixedLot = 0.01; // Fixed Lot
input bool EnableRiskPercent = true;                                // Enable Risk %
input double RiskPercent = 1.0;                                     // Risk %
input int TakeProfit = 1000;                                        // Take Profit (points)
input int StopLoss = 5000;                                          // Stop Loss (points)
input bool Stealth = false;                                         // Hide TP/SL

input group "=== BREAKEVEN & TRAILING ===" input bool EnableTrailingStop = true; // Enable Trailing
input int TrailingStopStart = 150;                                               // Trailing Start (points)
input int TrailingStopLevel = 80;                                                // Trailing Level (points)

input group "=== HIGH/LOW STRATEGY ===" input ENUM_TIMEFRAMES HighLowTimeframe = PERIOD_CURRENT; // High/Low Timeframe
input int BufferDistance = 90;                                                                   // Buffer Distance (points)
input int HighLowStartHour = 3;                                                                  // High/Low Start Hour
input int HighLowStartMinute = 0;                                                                // High/Low Start Minute
input int HighLowEndHour = 11;                                                                   // High/Low End Hour
input int HighLowEndMinute = 0;                                                                  // High/Low End Minute

input group "=== VISUALIZATION ===" input bool ShowHighLowLine = true; // Show High/Low Lines
input color HighLineColor = clrForestGreen;                            // High Line Color
input color LowLineColor = clrRed;                                     // Low Line Color

// === DCA SETTINGS ===
input bool EnableDCA = false;                // Activer le DCA
input double DcaLotMultiplier = 2.0;         // Multiplicateur de lot pour chaque entrée DCA
input double DcaMaxLot = 0.1;                // Lot maximum pour le DCA

// Global variables
CTrade trade;
datetime lastHighLowUpdate = 0;
double dailyHigh = 0;
double dailyLow = 0;
bool highLowCalculated = false;
bool ordersPlaced = false;
bool isConnected = false;
bool isSynchronized = false;
datetime lastSyncTime = 0; // Using GMT time
int syncRetryCount = 0;
const int MAX_SYNC_RETRIES = 3;

// Cache variables
datetime lastPositionCountTime = 0; // Using GMT time
int cachedTotalPositions = 0;
datetime lastSpreadCheckTime = 0; // Using GMT time
int cachedSpread = 0;

// Panel variables
string panelName = "TradingPanel";
int panelWidth = 200;      // Largeur du panel adaptée petit écran
int panelHeight = 300;
int panelX = 10;
int panelY = 20;
int lineHeight = 26;       // Plus d'espace entre les lignes
int fontSize = 11;         // Police plus grande
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

// Constants for error handling
const int MAX_RETRY_ATTEMPTS = 3;
const int RETRY_DELAY_MS = 1000; // 1 second delay between retries

// Error handling structure
struct ErrorInfo
{
   int errorCode;
   string errorMessage;
   datetime lastErrorTime;
   int retryCount;
};

// Global error tracking
ErrorInfo lastTradeError = {0, "", 0, 0};
ErrorInfo lastOrderError = {0, "", 0, 0};
ErrorInfo lastModifyError = {0, "", 0, 0};

//+------------------------------------------------------------------+
//| Logging function                                                   |
//+------------------------------------------------------------------+
void Log(string eventType, string details)
{
   string account = AccountInfoString(ACCOUNT_NAME);
   string symbol = Symbol();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = AccountInfoDouble(ACCOUNT_PROFIT);
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);

   // Format: Account|Symbol|Event|Details|Balance|Equity|Profit|Spread
   PrintFormat("%s|%s|%s|%s|%.2f|%.2f|%.2f|%d",
               account, symbol, eventType, details,
               balance, equity, profit, spread);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate input parameters
   if (MaxSpread <= 0)
   {
      Print("Error: MaxSpread must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (Slippage < 0)
   {
      Print("Error: Slippage cannot be negative");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (FixedLot <= 0)
   {
      Print("Error: FixedLot must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (EnableRiskPercent && RiskPercent <= 0)
   {
      Print("Error: RiskPercent must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (TakeProfit <= 0)
   {
      Print("Error: TakeProfit must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (StopLoss <= 0)
   {
      Print("Error: StopLoss must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (EnableTrailingStop)
   {
      if (TrailingStopStart <= 0)
      {
         Print("Error: TrailingStopStart must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
      if (TrailingStopLevel <= 0)
      {
         Print("Error: TrailingStopLevel must be positive");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   if (BufferDistance <= 0)
   {
      Print("Error: BufferDistance must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (BuyStopOrders <= 0)
   {
      Print("Error: BuyStopOrders must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (SellStopOrders <= 0)
   {
      Print("Error: SellStopOrders must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (MaxBuyEntries <= 0)
   {
      Print("Error: MaxBuyEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (MaxSellEntries <= 0)
   {
      Print("Error: MaxSellEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (MaxTotalEntries <= 0)
   {
      Print("Error: MaxTotalEntries must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (HighLowStartHour < 0 || HighLowStartHour > 23)
   {
      Print("Error: HighLowStartHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (HighLowStartMinute < 0 || HighLowStartMinute > 59)
   {
      Print("Error: HighLowStartMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (HighLowEndHour < 0 || HighLowEndHour > 23)
   {
      Print("Error: HighLowEndHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (HighLowEndMinute < 0 || HighLowEndMinute > 59)
   {
      Print("Error: HighLowEndMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (CloseOrdersHour < 0 || CloseOrdersHour > 23)
   {
      Print("Error: CloseOrdersHour must be between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (CloseOrdersMinute < 0 || CloseOrdersMinute > 59)
   {
      Print("Error: CloseOrdersMinute must be between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (MaxDailyBuyTrades <= 0)
   {
      Print("Error: MaxDailyBuyTrades must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (MaxDailySellTrades <= 0)
   {
      Print("Error: MaxDailySellTrades must be positive");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Check if High/Low calculation period is valid
   int startMinutes = HighLowStartHour * 60 + HighLowStartMinute;
   int endMinutes = HighLowEndHour * 60 + HighLowEndMinute;
   if (startMinutes >= endMinutes)
   {
      Print("Error: High/Low calculation period is invalid (start time must be before end time)");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialize trade object
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // Check connection
   if (!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Print("No connection to the server!");
      return INIT_FAILED;
   }

   // Check synchronization
   if (!IsSynchronized())
   {
      Print("Failed to synchronize with the server!");
      return INIT_FAILED;
   }

   CreateTradingPanel();

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Check if terminal is synchronized with server                      |
//+------------------------------------------------------------------+
bool IsSynchronized()
{
   if (TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      isSynchronized = true;
      lastSyncTime = TimeGMT(); // Using GMT time
      syncRetryCount = 0;
      return true;
   }

   if (syncRetryCount < MAX_SYNC_RETRIES)
   {
      syncRetryCount++;
      Print("Waiting for synchronization... Attempt ", syncRetryCount, " of ", MAX_SYNC_RETRIES);
      return false;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete graphical objects
   ObjectDelete(0, "DailyHigh");
   ObjectDelete(0, "DailyLow");

   DeleteTradingPanel();
}

//+------------------------------------------------------------------+
//| Get cached total positions count                                   |
//+------------------------------------------------------------------+
int GetCachedTotalPositions()
{
   if (TimeGMT() - lastPositionCountTime > 1)
   { // Update cache every second using GMT time
      cachedTotalPositions = CountTotalOpenPositions();
      lastPositionCountTime = TimeGMT();
   }
   return cachedTotalPositions;
}

//+------------------------------------------------------------------+
//| Get cached spread                                                  |
//+------------------------------------------------------------------+
int GetCachedSpread()
{
   if (TimeGMT() - lastSpreadCheckTime > 1)
   { // Update cache every second using GMT time
      cachedSpread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
      lastSpreadCheckTime = TimeGMT();
   }
   return cachedSpread;
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check connection
   if (!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      isConnected = false;
      Log("CONNECTION", "Connection lost");
      return;
   }

   if (!isConnected)
   {
      isConnected = true;
      Log("CONNECTION", "Connection restored");
   }

   // Check synchronization periodically
   if (TimeGMT() - lastSyncTime > 60)
   { // Using GMT time
      isSynchronized = IsSynchronized();
   }

   if (!isSynchronized)
   {
      return;
   }

   // Check spread using cache
   if (GetCachedSpread() > MaxSpread)
   {
      return;
   }

   // Check and update daily highs and lows
   UpdateDailyHighLow();

   // Place pending orders at 11:00 GMT
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
void UpdateDailyHighLow()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime); // Using GMT time

   // Check if we are in the calculation period (GMT)
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int startMinutes = HighLowStartHour * 60 + HighLowStartMinute;
   int endMinutes = HighLowEndHour * 60 + HighLowEndMinute;
   int closeMinutes = CloseOrdersHour * 60 + CloseOrdersMinute;

   // Reset at the start of the calculation period
   if (currentMinutes == startMinutes)
   {
      highLowCalculated = false;
      dailyHigh = 0;
      dailyLow = 0;
      ObjectDelete(0, "DailyHigh");
      ObjectDelete(0, "DailyLow");
      Log("RESET", "Resetting High/Low calculation at " + TimeToString(TimeGMT()));
   }

   // Calculate High/Low during the specified period
   if (currentMinutes >= startMinutes && currentMinutes <= endMinutes)
   {
      if (!highLowCalculated)
      {
         CalculateDailyHighLow();
         highLowCalculated = true;
      }
      else
      {
         // Get current bar data
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         if (CopyRates(Symbol(), HighLowTimeframe, 0, 1, rates) > 0)
         {
            // Update daily high/low if needed
            if (rates[0].high > dailyHigh)
            {
               dailyHigh = rates[0].high;
               Log("NEW", "New High found: " + DoubleToString(dailyHigh, 5) + " at " + TimeToString(rates[0].time));
            }
            if (rates[0].low < dailyLow)
            {
               dailyLow = rates[0].low;
               Log("NEW", "New Low found: " + DoubleToString(dailyLow, 5) + " at " + TimeToString(rates[0].time));
            }

            // Update line positions
            if (ShowHighLowLine)
            {
               // Delete existing lines
               ObjectDelete(0, "DailyHigh");
               ObjectDelete(0, "DailyLow");

               // Get start and end times for the current day (GMT)
               MqlDateTime startTime;
               TimeToStruct(TimeGMT(), startTime);
               startTime.hour = HighLowStartHour;
               startTime.min = HighLowStartMinute;
               startTime.sec = 0;
               datetime start = StructToTime(startTime);

               MqlDateTime endTime;
               TimeToStruct(TimeGMT(), endTime);
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
   // Delete lines at close time (GMT)
   else if (currentMinutes == closeMinutes)
   {
      highLowCalculated = false;
      ObjectDelete(0, "DailyHigh");
      ObjectDelete(0, "DailyLow");
      Log("DELETE", "Deleting High/Low lines at close time: " + TimeToString(TimeGMT()));
   }
}

//+------------------------------------------------------------------+
//| Calculate daily high and low                                       |
//+------------------------------------------------------------------+
void CalculateDailyHighLow()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // Get data from the start of the period
   MqlDateTime startTime;
   TimeToStruct(TimeGMT(), startTime);
   startTime.hour = HighLowStartHour;
   startTime.min = HighLowStartMinute;
   startTime.sec = 0;
   datetime start = StructToTime(startTime);

   MqlDateTime endTime;
   TimeToStruct(TimeGMT(), endTime);
   endTime.hour = HighLowEndHour;
   endTime.min = HighLowEndMinute;
   endTime.sec = 0;
   datetime end = StructToTime(endTime);

   // Use the selected timeframe for calculation
   if (CopyRates(Symbol(), HighLowTimeframe, start, end, rates) > 0)
   {
      // Initialize with first bar values
      dailyHigh = rates[0].high;
      dailyLow = rates[0].low;

      Log("START", "Starting High/Low calculation from " + TimeToString(start) + " to " + TimeToString(end));
      Log("FIRST", "First bar - High: " + DoubleToString(rates[0].high, 5) +
                       " Low: " + DoubleToString(rates[0].low, 5) +
                       " Open: " + DoubleToString(rates[0].open, 5) +
                       " Close: " + DoubleToString(rates[0].close, 5) +
                       " Time: " + TimeToString(rates[0].time));

      // Find true high and low including wicks
      for (int i = 1; i < ArraySize(rates); i++)
      {
         if (rates[i].high > dailyHigh)
         {
            dailyHigh = rates[i].high;
            Log("NEW", "New High found at " + TimeToString(rates[i].time) +
                           ": " + DoubleToString(dailyHigh, 5) +
                           " (Bar High: " + DoubleToString(rates[i].high, 5) +
                           " Open: " + DoubleToString(rates[i].open, 5) +
                           " Close: " + DoubleToString(rates[i].close, 5) + ")");
         }
         if (rates[i].low < dailyLow)
         {
            dailyLow = rates[i].low;
            Log("NEW", "New Low found at " + TimeToString(rates[i].time) +
                           ": " + DoubleToString(dailyLow, 5) +
                           " (Bar Low: " + DoubleToString(rates[i].low, 5) +
                           " Open: " + DoubleToString(rates[i].open, 5) +
                           " Close: " + DoubleToString(rates[i].close, 5) + ")");
         }
      }

      Log("FINAL", "Final Daily High: " + DoubleToString(dailyHigh, 5) + " Low: " + DoubleToString(dailyLow, 5));

      // Draw lines if enabled
      if (ShowHighLowLine)
      {
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

         Log("DRAW", "High/Low lines drawn from " + TimeToString(start) + " to " + TimeToString(end));
      }
   }
   else
   {
      Log("ERROR", "Failed to copy rates for High/Low calculation. Error: " + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Count total open positions                                         |
//+------------------------------------------------------------------+
int CountTotalOpenPositions()
{
   int count = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
             PositionGetInteger(POSITION_MAGIC) == Magic)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Place pending orders                                               |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime); // Using GMT time

   // Reset daily trade counters and ordersPlaced flag at midnight GMT
   if (lastTradeDate != currentTime.day)
   {
      dailyBuyTrades = 0;
      dailySellTrades = 0;
      ordersPlaced = false; // Reset the flag at midnight GMT
      lastTradeDate = currentTime.day;
   }

   // Check if it's time to place orders (GMT)
   if (currentTime.hour == HighLowEndHour && currentTime.min == HighLowEndMinute && !ordersPlaced)
   {
      // Delete existing orders
      DeleteAllPendingOrders();

      // Check total open positions using cache
      int totalPositions = GetCachedTotalPositions();
      if (totalPositions >= MaxTotalEntries)
      {
         Log("MAX", "Maximum total entries reached: " + IntegerToString(totalPositions));
         return;
      }

      // Calculate base prices for orders
      double buyStopPrice = dailyHigh + BufferDistance * Point();
      double sellStopPrice = dailyLow - BufferDistance * Point();

      // Place normal trades
      Log("NORMAL", "Placing normal trades");
      double lotSize = CalculateLotSize();

      if (TradeDirection == TRADE_BUY || TradeDirection == TRADE_BOTH)
      {
         if (dailyBuyTrades < MaxDailyBuyTrades)
         {
            int buyPositions = CountOpenPositions(ORDER_TYPE_BUY);
            if (buyPositions < MaxBuyEntries && totalPositions < MaxTotalEntries)
            {
               for (int i = 0; i < BuyStopOrders; i++)
               {
                  double tp = Stealth ? 0 : buyStopPrice + TakeProfit * Point();
                  double sl = Stealth ? 0 : buyStopPrice - StopLoss * Point();
                  double lotToUse = FixedLot;
                  if (EnableRiskPercent)
                  {
                      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                      double riskAmount = accountBalance * RiskPercent / 100.0;
                      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
                      double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
                      double lotBase = NormalizeDouble(riskAmount / (StopLoss * tickValue), 2);
                      lotBase = MathFloor(lotBase / lotStep) * lotStep;
                      if (EnableDCA)
                          lotToUse = MathMin(lotBase * MathPow(DcaLotMultiplier, i), DcaMaxLot);
                      else
                          lotToUse = lotBase;
                  }
                  else
                  {
                      if (EnableDCA)
                          lotToUse = MathMin(FixedLot * MathPow(DcaLotMultiplier, i), DcaMaxLot);
                      else
                          lotToUse = FixedLot;
                  }
                  if (!PlaceOrderWithRetry(ORDER_TYPE_BUY_STOP, lotToUse, buyStopPrice, sl, tp, Comments))
                  {
                     Log("ERROR", "Failed to place Buy Stop order " + IntegerToString(i + 1) + " of " + IntegerToString(BuyStopOrders) + " after " + IntegerToString(MAX_RETRY_ATTEMPTS) + " attempts");
                  }
                  else
                  {
                     dailyBuyTrades++;
                     Log("PLACED", "Placed Buy Stop order " + IntegerToString(i + 1) + " of " + IntegerToString(BuyStopOrders) + " at price: " + DoubleToString(buyStopPrice, 5) + " lot: " + DoubleToString(lotToUse, 2));
                     if (EnableDCA)
                        UpdateGroupTPAndTrailing(POSITION_TYPE_BUY);
                  }
               }
            }
         }
      }

      if (TradeDirection == TRADE_SELL || TradeDirection == TRADE_BOTH)
      {
         if (dailySellTrades < MaxDailySellTrades)
         {
            int sellPositions = CountOpenPositions(ORDER_TYPE_SELL);
            if (sellPositions < MaxSellEntries && totalPositions < MaxTotalEntries)
            {
               for (int i = 0; i < SellStopOrders; i++)
               {
                  double tp = Stealth ? 0 : sellStopPrice - TakeProfit * Point();
                  double sl = Stealth ? 0 : sellStopPrice + StopLoss * Point();
                  double lotToUse = FixedLot;
                  if (EnableRiskPercent)
                  {
                      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
                      double riskAmount = accountBalance * RiskPercent / 100.0;
                      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
                      double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
                      double lotBase = NormalizeDouble(riskAmount / (StopLoss * tickValue), 2);
                      lotBase = MathFloor(lotBase / lotStep) * lotStep;
                      if (EnableDCA)
                          lotToUse = MathMin(lotBase * MathPow(DcaLotMultiplier, i), DcaMaxLot);
                      else
                          lotToUse = lotBase;
                  }
                  else
                  {
                      if (EnableDCA)
                          lotToUse = MathMin(FixedLot * MathPow(DcaLotMultiplier, i), DcaMaxLot);
                      else
                          lotToUse = FixedLot;
                  }
                  if (!PlaceOrderWithRetry(ORDER_TYPE_SELL_STOP, lotToUse, sellStopPrice, sl, tp, Comments))
                  {
                     Log("ERROR", "Failed to place Sell Stop order " + IntegerToString(i + 1) + " of " + IntegerToString(SellStopOrders) + " after " + IntegerToString(MAX_RETRY_ATTEMPTS) + " attempts");
                  }
                  else
                  {
                     dailySellTrades++;
                     Log("PLACED", "Placed Sell Stop order " + IntegerToString(i + 1) + " of " + IntegerToString(SellStopOrders) + " at price: " + DoubleToString(sellStopPrice, 5) + " lot: " + DoubleToString(lotToUse, 2));
                     if (EnableDCA)
                        UpdateGroupTPAndTrailing(POSITION_TYPE_SELL);
                  }
               }
            }
         }
      }

      ordersPlaced = true;
      Log("SUCCESS", "Orders placed successfully. Total positions: " + IntegerToString(totalPositions));
   }

   // Reset flag at midnight GMT
   if (currentTime.hour == 0 && currentTime.min == 0)
   {
      ordersPlaced = false;
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk settings                          |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if (EnableRiskPercent)
   {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = accountBalance * RiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
      double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

      double lots = NormalizeDouble(riskAmount / (StopLoss * tickValue), 2);
      lots = MathFloor(lots / lotStep) * lotStep;

      return MathMin(lots, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX));
   }

   return FixedLot;
}

//+------------------------------------------------------------------+
//| Count open positions of specific type                              |
//+------------------------------------------------------------------+
int CountOpenPositions(ENUM_ORDER_TYPE type)
{
   int count = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
             PositionGetInteger(POSITION_MAGIC) == Magic &&
             PositionGetInteger(POSITION_TYPE) == type)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                          |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders(ENUM_ORDER_TYPE orderType = WRONG_VALUE)
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == Symbol() &&
             OrderGetInteger(ORDER_MAGIC) == Magic)
         {
            if (orderType == WRONG_VALUE || OrderGetInteger(ORDER_TYPE) == orderType)
            {
               if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ||
                   OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
               {
                  if (trade.OrderDelete(ticket))
                  {
                     Log("DELETE", "Deleted pending order. Ticket: " + IntegerToString(ticket));
                  }
                  else
                  {
                     Log("ERROR", "Failed to delete pending order. Error: " + IntegerToString(GetLastError()));
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                              |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   int buyPositions = 0;
   int sellPositions = 0;
   datetime today = TimeGMT() - (TimeGMT() % 86400);

   for (int i = 0; i < PositionsTotal(); i++)
   {
      if (PositionSelectByTicket(PositionGetTicket(i)))
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
             PositionGetInteger(POSITION_MAGIC) == Magic)
         {

            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
            datetime positionDate = positionTime - (positionTime % 86400);

            if (positionDate == today)
            {
               if (posType == POSITION_TYPE_BUY)
                  buyPositions++;
               else if (posType == POSITION_TYPE_SELL)
                  sellPositions++;
            }

            ulong ticket = PositionGetTicket(i);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);

            if (EnableTrailingStop)
            {
               double profitInPoints = posType == POSITION_TYPE_BUY ? (currentPrice - openPrice) / Point() : (openPrice - currentPrice) / Point();

               if (profitInPoints >= TrailingStopStart)
               {
                  double newSL = posType == POSITION_TYPE_BUY ? currentPrice - TrailingStopLevel * Point() : currentPrice + TrailingStopLevel * Point();

                  bool shouldModify = posType == POSITION_TYPE_BUY ? newSL > sl : newSL < sl || sl == 0;

                  if (shouldModify)
                  {
                     if (!ModifyPositionWithRetry(ticket, newSL, tp))
                     {
                        Log("ERROR", "Failed to modify position for Trailing Stop after " + IntegerToString(MAX_RETRY_ATTEMPTS) + " attempts");
                     }
                     else
                     {
                        Log("MODIFY", "Trailing Stop updated - Old SL: " + DoubleToString(sl, 5) +
                                          " New SL: " + DoubleToString(newSL, 5) +
                                          " Current Price: " + DoubleToString(currentPrice, 5) +
                                          " Direction: " + (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
                     }
                  }
               }
            }
         }
      }
   }

   if (DeleteOppositePendingOrders)
   {
      if (buyPositions >= BuyStopOrders)
      {
         Log("DELETE", "All buy positions activated (" + IntegerToString(buyPositions) +
                           "/" + IntegerToString(BuyStopOrders) +
                           "). Deleting all sell stop orders.");
         DeleteAllPendingOrders(ORDER_TYPE_SELL_STOP);
      }

      if (sellPositions >= SellStopOrders)
      {
         Log("DELETE", "All sell positions activated (" + IntegerToString(sellPositions) +
                           "/" + IntegerToString(SellStopOrders) +
                           "). Deleting all buy stop orders.");
         DeleteAllPendingOrders(ORDER_TYPE_BUY_STOP);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage pending orders                                              |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeGMT(), currentTime); // Using GMT time

   // Check if we are at or past closing time (GMT)
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   int closeMinutes = CloseOrdersHour * 60 + CloseOrdersMinute;

   if (currentMinutes >= closeMinutes)
   {
      // Check if we have already closed orders today
      static datetime lastCloseDate = 0;
      datetime currentDate = TimeGMT() - (TimeGMT() % 86400); // Current date at midnight GMT

      if (lastCloseDate != currentDate)
      {
         // Delete all pending orders
         int ordersDeleted = 0;
         for (int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong ticket = OrderGetTicket(i);
            if (ticket > 0)
            {
               if (OrderGetString(ORDER_SYMBOL) == Symbol() &&
                   OrderGetInteger(ORDER_MAGIC) == Magic)
               {
                  if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ||
                      OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
                  {
                     if (trade.OrderDelete(ticket))
                     {
                        ordersDeleted++;
                     }
                     else
                     {
                        Log("ERROR", "Failed to delete pending order. Error: " + IntegerToString(GetLastError()));
                     }
                  }
               }
            }
         }

         if (ordersDeleted > 0)
         {
            Log("CLOSE", "Closed " + IntegerToString(ordersDeleted) + " pending orders at " + TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES));
         }

         lastCloseDate = currentDate;
      }
   }
}

//+------------------------------------------------------------------+
//| Create Trading Panel                                              |
//+------------------------------------------------------------------+
void CreateTradingPanel()
{
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
   ObjectSetString(0, panelName + "_Title", OBJPROP_TEXT, "www.1pair1trade1day.com");
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
void UpdateTradingPanel()
{
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
   if (equity > maxEquity)
   {
      maxEquity = equity;
      minEquity = equity; // Reset minimum when reaching new maximum
   }
   if (equity < minEquity)
      minEquity = equity;

   // Calculate current and maximum drawdown
   double currentDrawdown = (maxEquity - minEquity) / maxEquity * 100;
   if (currentDrawdown > maxDrawdown)
      maxDrawdown = currentDrawdown;

   // Calculate total profit from closed trades
   double totalClosedProfit = 0;
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   for (int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket > 0)
      {
         if (HistoryDealGetString(ticket, DEAL_SYMBOL) == Symbol() &&
             HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic)
         {
            totalClosedProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }
   }

   // Calculate total lots from open positions
   totalLots = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0)
      {
         if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
             PositionGetInteger(POSITION_MAGIC) == Magic)
         {
            totalLots += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }

   // Current spread
   int spread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   color spreadColor = spread <= MaxSpread ? normalColor : warningColor;

   // Update information
   UpdatePanelLine("Balance: " + DoubleToString(balance, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Equity: " + DoubleToString(equity, 2), line++, yOffset, normalColor);
   UpdatePanelLine("Profit: " + DoubleToString(profit, 2), line++, yOffset, profit >= 0 ? profitColor : lossColor);
   UpdatePanelLine("Total Profit: " + DoubleToString(totalClosedProfit, 2), line++, yOffset, totalClosedProfit >= 0 ? profitColor : lossColor);
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
   for (int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket > 0)
      {
         if (OrderGetString(ORDER_SYMBOL) == Symbol() &&
             OrderGetInteger(ORDER_MAGIC) == Magic)
         {
            if (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP ||
                OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)
            {
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
void UpdatePanelLine(string text, int line, int yOffset, color lineColor)
{
   string lineName = panelName + "_Line" + IntegerToString(line);

   if (ObjectFind(0, lineName) < 0)
   {
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
void DeleteTradingPanel()
{
   ObjectsDeleteAll(0, panelName);
}

//+------------------------------------------------------------------+
//| Handle trade errors with retry logic                               |
//+------------------------------------------------------------------+
bool HandleTradeError(int errorCode, string operation)
{
   if (errorCode == 0)
      return true; // No error

   string errorMessage = "Error in " + operation + ": " + IntegerToString(errorCode) + " - " + GetLastErrorDescription(errorCode);
   Print(errorMessage);

   // Update error tracking
   lastTradeError.errorCode = errorCode;
   lastTradeError.errorMessage = errorMessage;
   lastTradeError.lastErrorTime = TimeGMT(); // Using GMT time
   lastTradeError.retryCount++;

   // Check if we should retry
   if (lastTradeError.retryCount < MAX_RETRY_ATTEMPTS)
   {
      Print("Retrying operation in ", RETRY_DELAY_MS, "ms... (Attempt ", lastTradeError.retryCount + 1, " of ", MAX_RETRY_ATTEMPTS, ")");
      Sleep(RETRY_DELAY_MS);
      return false;
   }

   // Reset retry count after max attempts
   lastTradeError.retryCount = 0;
   return true;
}

//+------------------------------------------------------------------+
//| Get detailed error description                                     |
//+------------------------------------------------------------------+
string GetLastErrorDescription(int errorCode)
{
   switch (errorCode)
   {
   case 1:
      return "No error returned";
   case 2:
      return "Common error";
   case 3:
      return "Invalid trade parameters";
   case 4:
      return "Trade server is busy";
   case 5:
      return "Old version of the client terminal";
   case 6:
      return "No connection with trade server";
   case 7:
      return "Not enough rights";
   case 8:
      return "Too frequent requests";
   case 9:
      return "Malfunctional trade operation";
   case 64:
      return "Account disabled";
   case 65:
      return "Invalid account";
   case 128:
      return "Trade timeout";
   case 129:
      return "Invalid price";
   case 130:
      return "Invalid stops";
   case 131:
      return "Invalid trade volume";
   case 132:
      return "Market is closed";
   case 133:
      return "Trade is disabled";
   case 134:
      return "Not enough money";
   case 135:
      return "Price changed";
   case 136:
      return "Off quotes";
   case 137:
      return "Broker is busy";
   case 138:
      return "Requote";
   case 139:
      return "Order is locked";
   case 140:
      return "Long positions only allowed";
   case 141:
      return "Too many requests";
   case 145:
      return "Modification denied because order is too close to market";
   case 146:
      return "Trade context is busy";
   case 147:
      return "Expirations are denied by broker";
   case 148:
      return "Too many open and pending orders";
   case 149:
      return "Hedging is prohibited";
   case 150:
      return "Prohibited by FIFO rules";
   default:
      return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Place order with error handling and retry                          |
//+------------------------------------------------------------------+
bool PlaceOrderWithRetry(ENUM_ORDER_TYPE orderType, double volume, double price, double sl, double tp, string comment)
{
   int attempts = 0;
   bool result = false;

   while (attempts < MAX_RETRY_ATTEMPTS)
   {
      if (orderType == ORDER_TYPE_BUY_STOP)
      {
         result = trade.BuyStop(volume, price, Symbol(), sl, tp, ORDER_TIME_SPECIFIED, TimeGMT() + 9 * 3600, comment);
      }
      else if (orderType == ORDER_TYPE_SELL_STOP)
      {
         result = trade.SellStop(volume, price, Symbol(), sl, tp, ORDER_TIME_SPECIFIED, TimeGMT() + 9 * 3600, comment);
      }

      if (result)
      {
         lastTradeError.retryCount = 0; // Reset retry count on success
         return true;
      }

      int errorCode = GetLastError();
      if (HandleTradeError(errorCode, "PlaceOrder"))
      {
         break; // Don't retry if error is not recoverable
      }

      attempts++;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Modify position with error handling and retry                      |
//+------------------------------------------------------------------+
bool ModifyPositionWithRetry(ulong ticket, double sl, double tp)
{
   int attempts = 0;
   bool result = false;

   // Vérifier si la position existe
   if (!PositionSelectByTicket(ticket))
   {
      Log("ERROR", "Position not found. Ticket: " + IntegerToString(ticket));
      return false;
   }

   // Récupérer les valeurs actuelles
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   // Vérifier si les nouveaux niveaux sont valides
   bool validStops = true;
   if (posType == POSITION_TYPE_BUY)
   {
      // Pour une position d'achat, SL doit être en dessous et TP au-dessus du prix actuel
      if (sl > 0 && sl >= currentPrice)
      {
         Log("ERROR", "Invalid Stop Loss for Buy position. SL: " + DoubleToString(sl, 5) +
                          " Current Price: " + DoubleToString(currentPrice, 5));
         validStops = false;
      }
      if (tp > 0 && tp <= currentPrice)
      {
         Log("ERROR", "Invalid Take Profit for Buy position. TP: " + DoubleToString(tp, 5) +
                          " Current Price: " + DoubleToString(currentPrice, 5));
         validStops = false;
      }
   }
   else if (posType == POSITION_TYPE_SELL)
   {
      // Pour une position de vente, SL doit être au-dessus et TP en dessous du prix actuel
      if (sl > 0 && sl <= currentPrice)
      {
         Log("ERROR", "Invalid Stop Loss for Sell position. SL: " + DoubleToString(sl, 5) +
                          " Current Price: " + DoubleToString(currentPrice, 5));
         validStops = false;
      }
      if (tp > 0 && tp >= currentPrice)
      {
         Log("ERROR", "Invalid Take Profit for Sell position. TP: " + DoubleToString(tp, 5) +
                          " Current Price: " + DoubleToString(currentPrice, 5));
         validStops = false;
      }
   }

   if (!validStops)
   {
      return false;
   }

   // Vérifier si les nouvelles valeurs sont différentes des anciennes
   if (currentSL == sl && currentTP == tp)
   {
      Log("NOCHANGE", "No changes needed - SL and TP are already at desired levels");
      return true;
   }

   while (attempts < MAX_RETRY_ATTEMPTS)
   {
      result = trade.PositionModify(ticket, sl, tp);

      if (result)
      {
         lastModifyError.retryCount = 0; // Reset retry count on success
         return true;
      }

      int errorCode = GetLastError();
      if (HandleTradeError(errorCode, "ModifyPosition"))
      {
         break; // Don't retry if error is not recoverable
      }

      attempts++;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Close position with error handling and retry                       |
//+------------------------------------------------------------------+
bool ClosePositionWithRetry(ulong ticket)
{
   int attempts = 0;
   bool result = false;

   while (attempts < MAX_RETRY_ATTEMPTS)
   {
      result = trade.PositionClose(ticket);

      if (result)
      {
         lastTradeError.retryCount = 0; // Reset retry count on success
         return true;
      }

      int errorCode = GetLastError();
      if (HandleTradeError(errorCode, "ClosePosition"))
      {
         break; // Don't retry if error is not recoverable
      }

      attempts++;
   }

   return false;
}

// === DCA UTILS ===
// Calcule la moyenne pondérée du prix d'entrée et le lot total pour une direction
void GetWeightedAveragePriceAndLot(ENUM_POSITION_TYPE direction, double &avgPrice, double &totalLot)
{
    avgPrice = 0;
    totalLot = 0;
    double weightedSum = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
                PositionGetInteger(POSITION_MAGIC) == Magic &&
                PositionGetInteger(POSITION_TYPE) == direction)
            {
                double lot = PositionGetDouble(POSITION_VOLUME);
                double price = PositionGetDouble(POSITION_PRICE_OPEN);
                weightedSum += price * lot;
                totalLot += lot;
            }
        }
    }
    if (totalLot > 0)
        avgPrice = weightedSum / totalLot;
}

// Met à jour le TP et trailing de toutes les positions d'un groupe (direction) selon la moyenne pondérée
void UpdateGroupTPAndTrailing(ENUM_POSITION_TYPE direction)
{
    double avgPrice, totalLot;
    GetWeightedAveragePriceAndLot(direction, avgPrice, totalLot);
    double newTP = 0;
    if (direction == POSITION_TYPE_BUY)
        newTP = avgPrice + TakeProfit * Point();
    else
        newTP = avgPrice - TakeProfit * Point();
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
                PositionGetInteger(POSITION_MAGIC) == Magic &&
                PositionGetInteger(POSITION_TYPE) == direction)
            {
                ulong ticket = PositionGetTicket(i);
                double sl = PositionGetDouble(POSITION_SL);
                ModifyPositionWithRetry(ticket, sl, newTP);
            }
        }
    }
    // Trailing groupé (optionnel)
    if (EnableTrailingStop && totalLot > 0)
    {
        double currentPrice = (direction == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double profitInPoints = (direction == POSITION_TYPE_BUY) ? (currentPrice - avgPrice) / Point() : (avgPrice - currentPrice) / Point();
        if (profitInPoints >= TrailingStopStart)
        {
            double newSL = (direction == POSITION_TYPE_BUY) ? currentPrice - TrailingStopLevel * Point() : currentPrice + TrailingStopLevel * Point();
            for (int i = 0; i < PositionsTotal(); i++)
            {
                if (PositionSelectByTicket(PositionGetTicket(i)))
                {
                    if (PositionGetString(POSITION_SYMBOL) == Symbol() &&
                        PositionGetInteger(POSITION_MAGIC) == Magic &&
                        PositionGetInteger(POSITION_TYPE) == direction)
                    {
                        ulong ticket = PositionGetTicket(i);
                        double tp = PositionGetDouble(POSITION_TP);
                        double oldSL = PositionGetDouble(POSITION_SL);
                        bool shouldModify = (direction == POSITION_TYPE_BUY) ? (newSL > oldSL) : (newSL < oldSL || oldSL == 0);
                        if (shouldModify)
                            ModifyPositionWithRetry(ticket, newSL, tp);
                    }
                }
            }
        }
    }
}
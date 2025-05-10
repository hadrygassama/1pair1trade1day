//+------------------------------------------------------------------+
//|                                              EmaRsiCrossover.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Input Parameters
input group "Moving Average Settings"
input ENUM_MA_METHOD MA_Method = MODE_EMA;    // MA Method (EMA/SMA)
input int FastMA_Period = 50;                 // Fast MA Period
input int SlowMA_Period = 200;                // Slow MA Period
input bool UseOppositeSignalExit = true;      // Exit on Opposite Signal

input group "RSI Settings"
input int RSI_Period = 14;                    // RSI Period
input double RSI_UpperLevel = 70;             // RSI Upper Level for Partial Close
input double RSI_LowerLevel = 30;             // RSI Lower Level for Partial Close
input double PartialClosePercent = 30;        // Partial Close Percentage (0 = disabled)
input int MinProfitForPartialClose = 100;      // Minimum Profit for Partial Close (points, 0 = disabled)

input group "Risk Management"
input bool UseFixedLot = true;               // Use Fixed Lot Size
input double FixedLotSize = 0.1;             // Fixed Lot Size (if UseFixedLot = true)
input double RiskPercent = 1.0;               // Risk Percent per Trade (if UseFixedLot = false)
input int StopLoss = 0;                      // Stop Loss (points, 0 = disabled)
input int TrailingStop = 0;                  // Trailing Stop (points, 0 = disabled)
input int TakeProfit = 0;                     // Take Profit (points, 0 = disabled)
input int BreakevenPoints = 0;               // Breakeven Points (0 = disabled)
input int MaxOpenPositions = 0;               // Maximum Open Positions
input double MaxExposurePercent = 0;         // Maximum Exposure Percent (0 = disabled, % of account balance)

input group "Volatility Filters"
input bool UseATRFilter = false;               // Use ATR Filter
input int ATR_Period = 14;                    // ATR Period
input double MinATR = 10;                     // Minimum ATR for Trading (0 = disabled)
input double MaxSpread = 400;                 // Maximum Spread (points, 0 = disabled)

input group "=== ADX Filter ==="
input bool UseAdxFilter = true;               // Enable ADX Filter
input ENUM_TIMEFRAMES AdxTimeframe = PERIOD_CURRENT;  // ADX timeframe
input int AdxPeriod = 14;                     // ADX Period
input double AdxMinThreshold = 25;            // Minimum ADX Threshold
input double AdxMaxThreshold = 100;            // Maximum ADX Threshold

input group "Trading Hours"
input string TradingStartTime = "00:00";      // Trading Start Time
input string TradingEndTime = "23:59";        // Trading End Time

// Global Variables
int fastMA_Handle;
int slowMA_Handle;
int rsi_Handle;
int atr_Handle;
int adx_Handle;  // Add ADX handle
datetime lastTradeTime = 0;
double point;
int minTradeDelaySeconds = 60; // Minimum delay between trades in seconds

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    fastMA_Handle = iMA(_Symbol, PERIOD_CURRENT, FastMA_Period, 0, MA_Method, PRICE_CLOSE);
    slowMA_Handle = iMA(_Symbol, PERIOD_CURRENT, SlowMA_Period, 0, MA_Method, PRICE_CLOSE);
    rsi_Handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    atr_Handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    adx_Handle = iADX(_Symbol, AdxTimeframe, AdxPeriod);  // Initialize ADX
    
    if(fastMA_Handle == INVALID_HANDLE || slowMA_Handle == INVALID_HANDLE || 
       rsi_Handle == INVALID_HANDLE || atr_Handle == INVALID_HANDLE ||
       adx_Handle == INVALID_HANDLE)
    {
        Print("Error creating indicators!");
        return(INIT_FAILED);
    }
    
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    IndicatorRelease(fastMA_Handle);
    IndicatorRelease(slowMA_Handle);
    IndicatorRelease(rsi_Handle);
    IndicatorRelease(atr_Handle);
    IndicatorRelease(adx_Handle);  // Release ADX handle
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsTradeAllowed()) return;
    
    // Update indicators
    double fastMA[], slowMA[], rsi[], atr[];
    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(fastMA_Handle, 0, 0, 3, fastMA) <= 0) return;
    if(CopyBuffer(slowMA_Handle, 0, 0, 3, slowMA) <= 0) return;
    if(CopyBuffer(rsi_Handle, 0, 0, 2, rsi) <= 0) return;
    if(CopyBuffer(atr_Handle, 0, 0, 1, atr) <= 0) return;
    
    // Check for signals
    CheckForSignals(fastMA, slowMA, rsi, atr[0]);
    
    // Manage open positions
    ManageOpenPositions(rsi[0]);
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
    // Check if enough time has passed since last trade
    if(TimeCurrent() - lastTradeTime < minTradeDelaySeconds)
    {
        return false;
    }
    
    // Check ADX filter
    if(UseAdxFilter)
    {
        double adxValues[];
        ArraySetAsSeries(adxValues, true);
        if(CopyBuffer(adx_Handle, 0, 0, 1, adxValues) <= 0) return false;
        
        double currentADX = adxValues[0];
        if(currentADX < AdxMinThreshold || currentADX > AdxMaxThreshold)
        {
            Print("ADX out of range: ", currentADX);
            return false;
        }
    }
    
    // Check spread
    if(MaxSpread > 0)
    {
        double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(currentSpread > MaxSpread)
        {
            Print("Spread too high: ", currentSpread);
            return false;
        }
    }
    
    // Check trading hours
    datetime currentTime = TimeCurrent();
    string currentTimeStr = TimeToString(currentTime, TIME_MINUTES);
    if(currentTimeStr < TradingStartTime || currentTimeStr > TradingEndTime)
    {
        return false;
    }
    
    // Check number of open positions
    if(MaxOpenPositions > 0 && PositionsTotal() >= MaxOpenPositions)
    {
        return false;
    }
    
    // Check maximum exposure
    if(MaxExposurePercent > 0)
    {
        double totalExposure = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
                totalExposure += PositionGetDouble(POSITION_VOLUME) * PositionGetDouble(POSITION_PRICE_OPEN);
            }
        }
        
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double exposurePercent = (totalExposure / accountBalance) * 100;
        
        if(exposurePercent >= MaxExposurePercent)
        {
            Print("Maximum exposure reached: ", exposurePercent, "%");
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckForSignals(const double &fastMA[], const double &slowMA[], 
                    const double &rsi[], const double atr)
{
    // Check if ATR is sufficient
    if(UseATRFilter && MinATR > 0 && atr < MinATR)
    {
        return;
    }
    
    // Check ADX filter
    if(UseAdxFilter)
    {
        double adxValues[];
        ArraySetAsSeries(adxValues, true);
        if(CopyBuffer(adx_Handle, 0, 0, 1, adxValues) <= 0) return;
        
        double currentADX = adxValues[0];
        if(currentADX < AdxMinThreshold || currentADX > AdxMaxThreshold)
        {
            return;
        }
    }
    
    // Check if we already have a position
    if(PositionsTotal() > 0)
    {
        return;
    }
    
    // Check for crossover signals
    bool buySignal = fastMA[1] > slowMA[1] && fastMA[2] <= slowMA[2];
    bool sellSignal = fastMA[1] < slowMA[1] && fastMA[2] >= slowMA[2];
    
    if(buySignal)
    {
        OpenPosition(ORDER_TYPE_BUY);
    }
    else if(sellSignal)
    {
        OpenPosition(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Open new position                                                |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
    double lotSize = CalculateLotSize(orderType);
    if(lotSize <= 0) return;
    
    // Update last trade time
    lastTradeTime = TimeCurrent();
    
    double price = (orderType == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double sl = (StopLoss > 0) ? 
                ((orderType == ORDER_TYPE_BUY) ? 
                 price - StopLoss * point : 
                 price + StopLoss * point) : 0;
    
    double tp = (TakeProfit > 0) ? 
                ((orderType == ORDER_TYPE_BUY) ? 
                 price + TakeProfit * point : 
                 price - TakeProfit * point) : 0;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 123456;
    request.comment = "EMA RSI Crossover";
    request.type_filling = ORDER_FILLING_FOK;
    
    if(!OrderSend(request, result))
    {
        Print("OrderSend error: ", GetLastError());
        return;
    }
    
    if(result.retcode == TRADE_RETCODE_DONE)
    {
        Print("Position opened successfully - Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
              ", Price: ", price,
              ", SL: ", sl > 0 ? sl : "Disabled",
              ", TP: ", tp > 0 ? tp : "Disabled");
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk or fixed lot                |
//+------------------------------------------------------------------+
double CalculateLotSize(ENUM_ORDER_TYPE orderType)
{
    if(UseFixedLot)
    {
        return FixedLotSize;
    }
    
    if(StopLoss <= 0) return 0.01; // Return minimum lot size if stop loss is disabled
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double lotSize = NormalizeDouble(riskAmount / (StopLoss * tickValue / tickSize), 2);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions(const double rsi)
{
    static double previousRSI = 0;
    static datetime lastBarTime = 0;
    static bool wasAboveUpperLevel = false;  // Pour suivre si le RSI était déjà au-dessus de 70
    static bool wasBelowLowerLevel = false;  // Pour suivre si le RSI était déjà en dessous de 30
    
    // Get current bar time
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    // Only process on new bar
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;
    
    // Get RSI values for current and previous bar
    double rsiValues[];
    ArraySetAsSeries(rsiValues, true);
    if(CopyBuffer(rsi_Handle, 0, 0, 2, rsiValues) <= 0) return;
    
    // Get MA values for signal check
    double fastMA[], slowMA[];
    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);
    if(CopyBuffer(fastMA_Handle, 0, 0, 3, fastMA) <= 0) return;
    if(CopyBuffer(slowMA_Handle, 0, 0, 3, slowMA) <= 0) return;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            double positionVolume = PositionGetDouble(POSITION_VOLUME);
            
            // Check for opposite signal exit
            if(UseOppositeSignalExit)
            {
                bool oppositeSignal = false;
                
                if(posType == POSITION_TYPE_BUY)
                {
                    // Check for sell signal (fast MA crosses below slow MA)
                    oppositeSignal = (fastMA[1] < slowMA[1] && fastMA[2] >= slowMA[2]);
                    if(oppositeSignal)
                    {
                        Print("Opposite signal detected for BUY position - Closing position");
                        ClosePartialPosition(PositionGetTicket(i), positionVolume); // Close entire position
                        continue; // Skip other checks for this position
                    }
                }
                else if(posType == POSITION_TYPE_SELL)
                {
                    // Check for buy signal (fast MA crosses above slow MA)
                    oppositeSignal = (fastMA[1] > slowMA[1] && fastMA[2] <= slowMA[2]);
                    if(oppositeSignal)
                    {
                        Print("Opposite signal detected for SELL position - Closing position");
                        ClosePartialPosition(PositionGetTicket(i), positionVolume); // Close entire position
                        continue; // Skip other checks for this position
                    }
                }
            }
            
            // Check for partial close based on RSI
            if(PartialClosePercent > 0)
            {
                double profitPoints = (posType == POSITION_TYPE_BUY) ? 
                                    (currentPrice - openPrice) / point : 
                                    (openPrice - currentPrice) / point;
                
                bool shouldClose = false;
                
                if(posType == POSITION_TYPE_BUY)
                {
                    // Vérifie si le RSI vient de passer au-dessus de 70
                    if(rsiValues[0] > RSI_UpperLevel && !wasAboveUpperLevel)
                    {
                        shouldClose = true;
                        wasAboveUpperLevel = true;
                        Print("RSI crossed UP level for BUY position - Current: ", DoubleToString(rsiValues[0], 2));
                    }
                    // Réinitialise le flag quand le RSI redescend en dessous de 70
                    else if(rsiValues[0] <= RSI_UpperLevel)
                    {
                        wasAboveUpperLevel = false;
                    }
                }
                else if(posType == POSITION_TYPE_SELL)
                {
                    // Vérifie si le RSI vient de passer en dessous de 30
                    if(rsiValues[0] < RSI_LowerLevel && !wasBelowLowerLevel)
                    {
                        shouldClose = true;
                        wasBelowLowerLevel = true;
                        Print("RSI crossed DOWN level for SELL position - Current: ", DoubleToString(rsiValues[0], 2));
                    }
                    // Réinitialise le flag quand le RSI remonte au-dessus de 30
                    else if(rsiValues[0] >= RSI_LowerLevel)
                    {
                        wasBelowLowerLevel = false;
                    }
                }
                
                if(shouldClose)
                {
                    if(MinProfitForPartialClose <= 0 || profitPoints >= MinProfitForPartialClose)
                    {
                        Print("Closing partial position - RSI condition met, Profit Points: ", DoubleToString(profitPoints, 2));
                        ClosePartialPosition(PositionGetTicket(i), positionVolume * PartialClosePercent / 100);
                    }
                }
            }
            
            // Check for breakeven only if StopLoss is enabled
            if(BreakevenPoints > 0 && StopLoss > 0)
            {
                double profitPoints = (posType == POSITION_TYPE_BUY) ? 
                                    (currentPrice - openPrice) / point : 
                                    (openPrice - currentPrice) / point;
                
                if(profitPoints >= BreakevenPoints)
                {
                    ModifyPositionStopLoss(PositionGetTicket(i), openPrice);
                }
            }
            
            // Apply trailing stop only if StopLoss is enabled
            if(TrailingStop > 0 && StopLoss > 0)
            {
                ApplyTrailingStop(PositionGetTicket(i), posType, currentPrice);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close partial position                                           |
//+------------------------------------------------------------------+
void ClosePartialPosition(ulong ticket, double volume)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    // Normalize volume according to broker's rules
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    volume = NormalizeDouble(volume, 2);
    volume = MathFloor(volume / lotStep) * lotStep;
    volume = MathMax(minLot, MathMin(maxLot, volume));
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = volume;
    request.deviation = 10;
    request.magic = 123456;
    request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(!OrderSend(request, result))
    {
        Print("ClosePartialPosition error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Modify position stop loss                                        |
//+------------------------------------------------------------------+
void ModifyPositionStopLoss(ulong ticket, double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    // Get current position details
    if(!PositionSelectByTicket(ticket)) return;
    
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Adjust stop loss to be slightly different from open price
    if(MathAbs(newSL - openPrice) < point)
    {
        if(posType == POSITION_TYPE_BUY)
            newSL = openPrice - point;
        else
            newSL = openPrice + point;
    }
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP);
    
    if(!OrderSend(request, result))
    {
        Print("ModifyPositionStopLoss error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, ENUM_POSITION_TYPE posType, double currentPrice)
{
    double currentSL = PositionGetDouble(POSITION_SL);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    
    double newSL = 0;
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - TrailingStop * point;
        if(newSL > currentSL && newSL < currentPrice)
        {
            ModifyPositionStopLoss(ticket, newSL);
        }
    }
    else
    {
        newSL = currentPrice + TrailingStop * point;
        if(newSL < currentSL && newSL > currentPrice)
        {
            ModifyPositionStopLoss(ticket, newSL);
        }
    }
} 
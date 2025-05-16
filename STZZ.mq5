//+------------------------------------------------------------------+
//|                                                    STZZ.mq5 |
//|                                                                     |
//|                                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                           |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                       |
//+------------------------------------------------------------------+
enum ENUM_LOT_TYPE
{
    LOT_TYPE_FIXED = 0,    // Fixed Lot Size
    LOT_TYPE_RISK = 1      // Risk Based
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// Magic Number
input int      Magic = 548762;         // Magic Number

// Supertrend Settings
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe
input int    ATR_Period = 10;        // ATR Period
input double ATR_Multiplier = 3.0;   // ATR Multiplier

// ZigZag Settings
input int    ZigZag_Depth = 12;      // Depth
input int    ZigZag_Deviation = 5;   // Deviation
input int    ZigZag_Backstep = 3;    // Backstep

// Trade Settings
input ENUM_LOT_TYPE LotType = LOT_TYPE_FIXED;  // Lot Size Type
input double LotSize = 1;          // Fixed Lot Size
input double RiskPercent = 1.0;      // Risk % per Trade
input int      FixedTP = 0;       // Take Profit (points, 0=disabled)
input int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
input int      Buffer = 100;        // Order Buffer (points)
input bool     CheckExistingPositions = true;  // Check Existing Positions

// RSI Partial Close Settings
input bool     EnableRSIPartialClose = true;    // Enable RSI Partial Close
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_CURRENT;  // RSI Timeframe
input int      RSI_Period = 14;                  // RSI Period
input double   RSI_UpperLevel = 70;             // RSI Upper Level for Partial Close
input double   RSI_LowerLevel = 30;             // RSI Lower Level for Partial Close
input double   PartialClosePercent = 33;        // Partial Close Percentage (0=disabled)
input int      MinProfitForPartialClose = 100;  // Min Profit for Partial Close (points, 0=disabled)

// Trailing Stop
input int      TrailingStop = 0;   // Distance (points, 0=disabled)
input int      TrailingStep = 0;   // Step (points)

// Trade Limits
input int      MaxDailyBuyTrades = 0;    // Max Daily Buy (0=unlimited)
input int      MaxDailySellTrades = 0;   // Max Daily Sell (0=unlimited)
input int      MaxDailyTrades = 0;     // Max Daily Trades (0=unlimited)
input int      MaxBuyTrades = 0;         // Max Buy (0=unlimited)
input int      MaxSellTrades = 0;        // Max Sell (0=unlimited)
input int      MaxTrades = 0;          // Max Total Trades (0=unlimited)

// Trading Hours
input int      TimeStartHour = 0;      // Start Hour
input int      TimeStartMinute = 0;    // Start Minute
input int      TimeEndHour = 23;       // End Hour
input int      TimeEndMinute = 59;     // End Minute
input bool     AutoDetectBrokerOffset = false;  // Auto Detect GMT Offset
input bool     BrokerIsAheadOfGMT = true;       // Broker Ahead of GMT
input int      ManualBrokerOffset = 3;          // Manual GMT Offset (hours)

// Spread and Slippage
input int      MaxSpread = 40;         // Max Spread (pips)
input int      Slippage = 3;           // Slippage (points)
input bool     CloseOnOppositeSupertrend = true;  // Close on Trend Change

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade trade;                         // Trading object
int stHandle;           // Supertrend indicator handle
int zzHandle;           // ZigZag indicator handle
int rsiHandle;          // RSI indicator handle
ulong posTicket;        // Position ticket
double lotSize;         // Lot size
bool tslActive;         // Trailing stop loss active
double lastRSI;        // Last RSI value
bool rsiPartialCloseDone;
double lastZigZagHigh = 0;           // Last ZigZag high value
double lastZigZagLow = 0;            // Last ZigZag low value
double previousZigZagHigh = 0;       // Previous ZigZag high value
double previousZigZagLow = 0;        // Previous ZigZag low value
bool isFirstSignalAfterBullish = false;  // Flag for first signal after bullish Supertrend
bool isFirstSignalAfterBearish = false;  // Flag for first signal after bearish Supertrend
double lastLowBeforeBullish = 0;  // Pour le premier Low après tendance haussière
double lastHighBeforeBearish = 0; // Pour le premier High après tendance baissière

// Cache variables for optimization
datetime lastTradeCheck = 0;
int lastTotalTrades = 0;
int lastBuyTrades = 0;
int lastSellTrades = 0;
datetime lastDailyCheck = 0;
int lastDailyTrades = 0;
int lastDailyBuyTrades = 0;
int lastDailySellTrades = 0;
double lastSpread = 0;
datetime lastSpreadCheck = 0;
double lastClose1 = 0;
double lastClose2 = 0;
datetime lastPriceCheck = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(Slippage);
    
    // Initialize indicators
    stHandle = iCustom(_Symbol, Timeframe, "Supertrend.ex5", 
                      ATR_Period, ATR_Multiplier);
    zzHandle = iCustom(_Symbol, Timeframe, "ZigZag.ex5",
                      ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
    
    if(stHandle == INVALID_HANDLE)
    {
        Print("Error initializing Supertrend indicator for ", _Symbol);
        return(INIT_FAILED);
    }
    
    if(zzHandle == INVALID_HANDLE)
    {
        Print("Error initializing ZigZag indicator for ", _Symbol);
        return(INIT_FAILED);
    }
    
    // Initialize RSI indicator if partial close is enabled
    if(EnableRSIPartialClose)
    {
        rsiHandle = iRSI(_Symbol, RSI_Timeframe, RSI_Period, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            Print("Error initializing RSI indicator for ", _Symbol);
            return(INIT_FAILED);
        }
    }
    
    lastRSI = 0;
    rsiPartialCloseDone = false;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(stHandle != INVALID_HANDLE)
        IndicatorRelease(stHandle);
    if(zzHandle != INVALID_HANDLE)
        IndicatorRelease(zzHandle);
    if(rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop Loss                                          |
//+------------------------------------------------------------------+
void HandleTrailingStopLoss(const double &st[])
{
    if(TrailingStop <= 0 || TrailingStep <= 0) return;
    
    if(posTicket > 0)
    {
        if(PositionSelectByTicket(posTicket))
        {
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double posTp = PositionGetDouble(POSITION_TP);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
            {
                double profitPoints = (currentPrice - openPrice) / _Point;
                
                if(profitPoints >= TrailingStop)
                {
                    double newSL = currentPrice - TrailingStep * _Point;
                    if(newSL > currentSL || currentSL == 0)
                    {
                        trade.PositionModify(posTicket, newSL, posTp);
                    }
                }
            } 
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) 
            {
                double profitPoints = (openPrice - currentPrice) / _Point;
                
                if(profitPoints >= TrailingStop)
                {
                    double newSL = currentPrice + TrailingStep * _Point;
                    if(newSL < currentSL || currentSL == 0)
                    {
                        trade.PositionModify(posTicket, newSL, posTp);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Position Size                                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stopLoss, double entryPrice, bool isBuy)
{
    if(LotType == LOT_TYPE_FIXED)
        return LotSize;
        
    static double accountBalance = 0;
    static double tickSize = 0;
    static double tickValue = 0;
    static double pointValue = 0;
    static datetime lastCalc = 0;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - lastCalc > 60) // Update every minute
    {
        accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        pointValue = tickValue / tickSize;
        lastCalc = currentTime;
    }
    
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double stopLossPoints = MathAbs(entryPrice - stopLoss) / _Point;
    double takeProfitPoints = stopLossPoints * FixedTP / _Point;
    double totalRiskPoints = stopLossPoints + takeProfitPoints;
    
    double positionSize = NormalizeDouble(riskAmount / (totalRiskPoints * pointValue), 2);
    
    static double minLot = 0;
    static double maxLot = 0;
    static double lotStep = 0;
    
    if(minLot == 0)
    {
        minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    }
    
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    positionSize = NormalizeDouble(positionSize / lotStep, 0) * lotStep;
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    datetime currentTime = TimeCurrent();
    if(currentTime - lastSpreadCheck < 1) // Check every second
        return (lastSpread <= MaxSpread);
        
    lastSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    lastSpreadCheck = currentTime;
    return (lastSpread <= MaxSpread);
}

//+------------------------------------------------------------------+
//| Check trade limits                                                 |
//+------------------------------------------------------------------+
bool IsTradeAllowed(bool isBuy)
{
    datetime currentTime = TimeCurrent();
    
    // Check total trades
    if(MaxTrades > 0)
    {
        if(currentTime - lastTradeCheck < 1) // Check every second
        {
            if(lastTotalTrades >= MaxTrades)
                return false;
        }
        else
        {
            lastTotalTrades = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
                if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
                    lastTotalTrades++;
            }
            lastTradeCheck = currentTime;
            if(lastTotalTrades >= MaxTrades)
                return false;
        }
    }
    
    // Check trades by type
    if(isBuy && MaxBuyTrades > 0)
    {
        if(currentTime - lastTradeCheck < 1)
        {
            if(lastBuyTrades >= MaxBuyTrades)
                return false;
        }
        else
        {
            lastBuyTrades = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
                if(PositionGetSymbol(i) == _Symbol && 
                   PositionGetInteger(POSITION_MAGIC) == Magic &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    lastBuyTrades++;
            }
            if(lastBuyTrades >= MaxBuyTrades)
                return false;
        }
    }
    else if(!isBuy && MaxSellTrades > 0)
    {
        if(currentTime - lastTradeCheck < 1)
        {
            if(lastSellTrades >= MaxSellTrades)
                return false;
        }
        else
        {
            lastSellTrades = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
                if(PositionGetSymbol(i) == _Symbol && 
                   PositionGetInteger(POSITION_MAGIC) == Magic &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    lastSellTrades++;
            }
            if(lastSellTrades >= MaxSellTrades)
                return false;
        }
    }
    
    // Check daily trades
    if(MaxDailyTrades > 0 || (isBuy && MaxDailyBuyTrades > 0) || (!isBuy && MaxDailySellTrades > 0))
    {
        datetime today = StringToTime(TimeToString(currentTime, TIME_DATE));
        
        if(currentTime - lastDailyCheck < 60) // Check every minute
        {
            if(MaxDailyTrades > 0 && lastDailyTrades >= MaxDailyTrades)
                return false;
            if(isBuy && MaxDailyBuyTrades > 0 && lastDailyBuyTrades >= MaxDailyBuyTrades)
                return false;
            if(!isBuy && MaxDailySellTrades > 0 && lastDailySellTrades >= MaxDailySellTrades)
                return false;
        }
        else
        {
            lastDailyTrades = 0;
            lastDailyBuyTrades = 0;
            lastDailySellTrades = 0;
            
            HistorySelect(today, currentTime);
            for(int i = 0; i < HistoryDealsTotal(); i++)
            {
                ulong ticket = HistoryDealGetTicket(i);
                if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic)
                {
                    lastDailyTrades++;
                    if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
                    {
                        if(HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY)
                            lastDailyBuyTrades++;
                        else if(HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_SELL)
                            lastDailySellTrades++;
                    }
                }
            }
            lastDailyCheck = currentTime;
            
            if(MaxDailyTrades > 0 && lastDailyTrades >= MaxDailyTrades)
                return false;
            if(isBuy && MaxDailyBuyTrades > 0 && lastDailyBuyTrades >= MaxDailyBuyTrades)
                return false;
            if(!isBuy && MaxDailySellTrades > 0 && lastDailySellTrades >= MaxDailySellTrades)
                return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Delete all pending orders of specified type                        |
//+------------------------------------------------------------------+
void DeletePendingOrders(ENUM_ORDER_TYPE orderType)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
               OrderGetInteger(ORDER_MAGIC) == Magic && 
               OrderGetInteger(ORDER_TYPE) == orderType)
            {
                trade.OrderDelete(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if position exists for symbol                                  |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE posType)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == posType)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Handle Buy Signal                                                  |
//+------------------------------------------------------------------+
void HandleBuySignal(const double &st[], double close1, double close2, const double &zigzagHighLow[], const double &zigzag[])
{
    if(CheckExistingPositions && HasPosition(POSITION_TYPE_BUY))
        return;

    // Vérifier si un ordre en attente existe déjà
    bool pendingOrderExists = false;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i))
        {
            if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
               OrderGetInteger(ORDER_MAGIC) == Magic && 
               OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)
            {
                pendingOrderExists = true;
                break;
            }
        }
    }

    if(pendingOrderExists)
        return;

    if(close1 < st[1] && close2 > st[0])
    {
        isFirstSignalAfterBearish = true;
        isFirstSignalAfterBullish = false;
        
        if(!IsSpreadAcceptable())
            return;
        
        if(!IsTradeAllowed(true))
            return;
        
        double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        double buyOrderPrice = lastZigZagHigh + Buffer * _Point;
        buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
        
        if(buyOrderPrice <= currentAsk)
        {
            buyOrderPrice = currentAsk + _Point;
            buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
        }
        
        double sl = 0;
        if(FixedSL > 0)
        {
            sl = buyOrderPrice - FixedSL * _Point;
            sl = NormalizeDouble(sl, _Digits);
        }
        
        double tp = 0;
        if(FixedTP > 0)
        {
            tp = buyOrderPrice + FixedTP * _Point;
            tp = NormalizeDouble(tp, _Digits);
        }
        
        double lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
        datetime expiration = 0;
        
        if(trade.BuyStop(lotSize, buyOrderPrice, _Symbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            posTicket = trade.ResultOrder();
            isFirstSignalAfterBullish = false;
            lastLowBeforeBullish = 0.0;
        }
        else
        {
            Print("Failed to place Buy Stop order. Error: ", GetLastError());
            isFirstSignalAfterBullish = false;
            lastLowBeforeBullish = 0.0;
        }
    }
    
    if(isFirstSignalAfterBullish && close1 > st[1])
    {
        if(zigzagHighLow[0] == 0.0 && lastZigZagLow != 0.0)
        {
            if(lastLowBeforeBullish == 0.0 && zigzag[0] != 0.0 && previousZigZagLow != 0.0 && zigzag[0] != previousZigZagLow)
            {
                lastLowBeforeBullish = lastZigZagLow;
                
                if(!IsSpreadAcceptable())
                    return;
                
                if(!IsTradeAllowed(true))
                    return;
                
                double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                
                double buyOrderPrice = lastZigZagHigh + Buffer * _Point;
                buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
                
                if(buyOrderPrice <= currentAsk)
                {
                    buyOrderPrice = currentAsk + _Point;
                    buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
                }
                
                double sl = 0;
                if(FixedSL > 0)
                {
                    sl = buyOrderPrice - FixedSL * _Point;
                    sl = NormalizeDouble(sl, _Digits);
                }
                
                double tp = 0;
                if(FixedTP > 0)
                {
                    tp = buyOrderPrice + FixedTP * _Point;
                    tp = NormalizeDouble(tp, _Digits);
                }
                
                double lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
                datetime expiration = 0;
                
                if(trade.BuyStop(lotSize, buyOrderPrice, _Symbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    posTicket = trade.ResultOrder();
                    isFirstSignalAfterBullish = false;
                    lastLowBeforeBullish = 0.0;
                }
                else
                {
                    Print("Failed to place Buy Stop order. Error: ", GetLastError());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Sell Signal                                                 |
//+------------------------------------------------------------------+
void HandleSellSignal(const double &st[], double close1, double close2, const double &zigzagHighLow[], const double &zigzag[])
{
    if(CheckExistingPositions && HasPosition(POSITION_TYPE_SELL))
        return;

    if(close1 > st[1] && close2 < st[0])
    {
        isFirstSignalAfterBullish = true;
        isFirstSignalAfterBearish = false;
        
        if(!IsSpreadAcceptable())
            return;
        
        if(!IsTradeAllowed(false))
            return;
        
        DeletePendingOrders(ORDER_TYPE_SELL_STOP);
        
        double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        double sellOrderPrice = lastZigZagLow - Buffer * _Point;
        sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
        
        if(sellOrderPrice >= currentBid)
        {
            sellOrderPrice = currentBid - _Point;
            sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
        }
        
        double sl = 0;
        if(FixedSL > 0)
        {
            sl = sellOrderPrice + FixedSL * _Point;
            sl = NormalizeDouble(sl, _Digits);
        }
        
        double tp = 0;
        if(FixedTP > 0)
        {
            tp = sellOrderPrice - FixedTP * _Point;
            tp = NormalizeDouble(tp, _Digits);
        }
        
        double lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
        datetime expiration = 0;
        
        if(trade.SellStop(lotSize, sellOrderPrice, _Symbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            posTicket = trade.ResultOrder();
            isFirstSignalAfterBearish = false;
            lastHighBeforeBearish = 0.0;
        }
        else
        {
            Print("Failed to place Sell Stop order. Error: ", GetLastError());
            isFirstSignalAfterBearish = false;
            lastHighBeforeBearish = 0.0;
        }
    }
    
    if(isFirstSignalAfterBearish && close1 < st[1])
    {
        if(zigzagHighLow[0] != 0.0 && lastZigZagHigh != 0.0)
        {
            if(lastHighBeforeBearish == 0.0 && zigzag[0] != 0.0 && previousZigZagHigh != 0.0 && zigzag[0] != previousZigZagHigh)
            {
                lastHighBeforeBearish = lastZigZagHigh;
                
                if(!IsSpreadAcceptable())
                    return;
                
                if(!IsTradeAllowed(false))
                    return;
                
                DeletePendingOrders(ORDER_TYPE_SELL_STOP);
                
                double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                
                double sellOrderPrice = lastZigZagLow - Buffer * _Point;
                sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
                
                if(sellOrderPrice >= currentBid)
                {
                    sellOrderPrice = currentBid - _Point;
                    sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
                }
                
                double sl = 0;
                if(FixedSL > 0)
                {
                    sl = sellOrderPrice + FixedSL * _Point;
                    sl = NormalizeDouble(sl, _Digits);
                }
                
                double tp = 0;
                if(FixedTP > 0)
                {
                    tp = sellOrderPrice - FixedTP * _Point;
                    tp = NormalizeDouble(tp, _Digits);
                }
                
                double lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
                datetime expiration = 0;
                
                if(trade.SellStop(lotSize, sellOrderPrice, _Symbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    posTicket = trade.ResultOrder();
                    isFirstSignalAfterBearish = false;
                    lastHighBeforeBearish = 0.0;
                }
                else
                {
                    Print("Failed to place Sell Stop order. Error: ", GetLastError());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    static datetime lastCheck = 0;
    static bool lastResult = false;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - lastCheck < 1) // Check every second
        return lastResult;
        
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    int currentHour = time.hour;
    int currentMinute = time.min;
    
    if(AutoDetectBrokerOffset)
    {
        int brokerOffset = (int)TimeLocal() - (int)TimeGMT();
        currentHour = (currentHour - brokerOffset + 24) % 24;
    }
    else
    {
        int offset = BrokerIsAheadOfGMT ? ManualBrokerOffset : -ManualBrokerOffset;
        currentHour = (currentHour - offset + 24) % 24;
    }
    
    int currentTimeInMinutes = currentHour * 60 + currentMinute;
    int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
    int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
    
    if(endTimeInMinutes < startTimeInMinutes)
    {
        lastResult = (currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes <= endTimeInMinutes);
    }
    else
    {
        lastResult = (currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes <= endTimeInMinutes);
    }
    
    lastCheck = currentTime;
    return lastResult;
}

//+------------------------------------------------------------------+
//| Check ZigZag Signal                                                |
//+------------------------------------------------------------------+
bool IsZigZagBuySignal(const double &zigzag[], const double &zigzagHighLow[])
{
    if(zigzagHighLow[1] == 0.0 && zigzagHighLow[0] != 0.0)
    {
        if(zigzag[0] > zigzag[1])
        {
            return true;
        }
    }
    return false;
}

bool IsZigZagSellSignal(const double &zigzag[], const double &zigzagHighLow[])
{
    if(zigzagHighLow[1] != 0.0 && zigzagHighLow[0] == 0.0)
    {
        if(zigzag[0] < zigzag[1])
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Handle RSI Partial Close                                           |
//+------------------------------------------------------------------+
void HandleRSIPartialClose()
{
    if(!EnableRSIPartialClose || PartialClosePercent <= 0 || MinProfitForPartialClose <= 0)
        return;
        
    if(posTicket <= 0)
        return;
        
    if(!PositionSelectByTicket(posTicket))
        return;
        
    double rsi[];
    ArraySetAsSeries(rsi, true);
    if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) <= 0)
        return;
        
    double currentRSI = rsi[0];
    double previousRSI = lastRSI;
    lastRSI = currentRSI;
    
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double positionVolume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double profitPoints = 0;
    if(posType == POSITION_TYPE_BUY)
        profitPoints = (currentPrice - openPrice) / _Point;
    else if(posType == POSITION_TYPE_SELL)
        profitPoints = (openPrice - currentPrice) / _Point;
        
    if(profitPoints < MinProfitForPartialClose)
        return;
        
    if(posType == POSITION_TYPE_BUY)
    {
        if(previousRSI < RSI_UpperLevel && currentRSI > RSI_UpperLevel && !rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(trade.PositionClosePartial(posTicket, closeVolume))
            {
                rsiPartialCloseDone = true;
            }
        }
        else if(currentRSI < RSI_UpperLevel)
        {
            rsiPartialCloseDone = false;
        }
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        if(previousRSI > RSI_LowerLevel && currentRSI < RSI_LowerLevel && !rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(trade.PositionClosePartial(posTicket, closeVolume))
            {
                rsiPartialCloseDone = true;
            }
        }
        else if(currentRSI > RSI_LowerLevel)
        {
            rsiPartialCloseDone = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsWithinTradingHours())
        return;
        
    double st[];
    double zigzag[];
    double zigzagHighLow[];
        
    int copied = CopyBuffer(stHandle, 0, 0, 3, st);
    if(copied <= 0)
    {
        Print("Error CopyBuffer Supertrend: ", GetLastError());
        return;
    }
    
    if(zzHandle == INVALID_HANDLE)
    {
        Print("Error initializing ZigZag indicator for ", _Symbol);
        return;
    }

    copied = CopyBuffer(zzHandle, 0, 0, 3, zigzag);
    if(copied <= 0)
    {
        Print("Error copying ZigZag main buffer: ", GetLastError(), " for ", _Symbol);
        return;
    }
    
    copied = CopyBuffer(zzHandle, 1, 0, 3, zigzagHighLow);
    if(copied <= 0)
    {
        Print("Error copying ZigZag HighLow buffer: ", GetLastError(), " for ", _Symbol);
        return;
    }

    datetime currentTime = TimeCurrent();
    if(currentTime - lastPriceCheck < 1) // Check every second
    {
        if(lastClose1 == 0 || lastClose2 == 0)
        {
            lastClose1 = iClose(_Symbol, Timeframe, 1);
            lastClose2 = iClose(_Symbol, Timeframe, 2);
            lastPriceCheck = currentTime;
        }
    }
    else
    {
        lastClose1 = iClose(_Symbol, Timeframe, 1);
        lastClose2 = iClose(_Symbol, Timeframe, 2);
        lastPriceCheck = currentTime;
    }
    
    if(lastClose1 == 0 || lastClose2 == 0)
    {
        Print("Warning: Invalid close prices for ", _Symbol);
        return;
    }
    
    HandleTrailingStopLoss(st);
    
    if(zigzagHighLow[0] != 0.0)
    {
        if(lastZigZagHigh != zigzag[0] && zigzag[0] != 0.0)
        {
            previousZigZagHigh = lastZigZagHigh;
            Print("ZigZag High changed from ", lastZigZagHigh, " to ", zigzag[0], " (Change: ", zigzag[0] - lastZigZagHigh, " points)");
            lastZigZagHigh = zigzag[0];
        }
    }
    else
    {
        if(lastZigZagLow != zigzag[0] && zigzag[0] != 0.0)
        {
            previousZigZagLow = lastZigZagLow;
            Print("ZigZag Low changed from ", lastZigZagLow, " to ", zigzag[0], " (Change: ", zigzag[0] - lastZigZagLow, " points)");
            lastZigZagLow = zigzag[0];
        }
    }
    
    if(CloseOnOppositeSupertrend)
    {
        if(lastClose1 < st[1] && lastClose2 > st[0])
        {
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
                if(PositionSelectByTicket(PositionGetTicket(j)))
                {
                    if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                       PositionGetInteger(POSITION_MAGIC) == Magic &&
                       PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                        trade.PositionClose(PositionGetTicket(j));
                    }
                }
            }
        }
        
        if(lastClose1 > st[1] && lastClose2 < st[0])
        {
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
                if(PositionSelectByTicket(PositionGetTicket(j)))
                {
                    if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                       PositionGetInteger(POSITION_MAGIC) == Magic &&
                       PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    {
                        trade.PositionClose(PositionGetTicket(j));
                    }
                }
            }
        }
    }
    
    HandleBuySignal(st, lastClose1, lastClose2, zigzagHighLow, zigzag);
    HandleSellSignal(st, lastClose1, lastClose2, zigzagHighLow, zigzag);
    
    if(EnableRSIPartialClose)
    {
        HandleRSIPartialClose();
    }
    
    if(ArraySize(st) >= 3 && ArraySize(zigzag) >= 3 && ArraySize(zigzagHighLow) >= 3)
    {
        string zigzagSignal = "";
        if(IsZigZagBuySignal(zigzag, zigzagHighLow))
            zigzagSignal = "BUY SIGNAL";
        else if(IsZigZagSellSignal(zigzag, zigzagHighLow))
            zigzagSignal = "SELL SIGNAL";
        
        Comment("=== Supertrend Values ===\n",
                "ST[0]: ", st[0], "\n",
                "ST[1]: ", st[1], "\n",
                "ST[2]: ", st[2], "\n",
                "\n=== ZigZag Values ===\n",
                "Last High: ", lastZigZagHigh, "\n",
                "Last Low: ", lastZigZagLow, "\n",
                "Current ZigZag[0]: ", zigzag[0], " (", zigzagHighLow[0] == 0.0 ? "Low" : "High", ")\n",
                "\n=== Current Signal ===\n",
                "ZigZag Signal: ", zigzagSignal, "\n",
                "Position Ticket: ", posTicket, "\n",
                "\n=== ZigZag Parameters ===\n",
                "Depth: ", ZigZag_Depth, "\n",
                "Deviation: ", ZigZag_Deviation, "\n",
                "Backstep: ", ZigZag_Backstep, "\n",
                "\n=== Price Info ===\n",
                "Close[1]: ", lastClose1, "\n",
                "Close[2]: ", lastClose2);
    }
}

//+------------------------------------------------------------------+
//| Trade function                                                    |
//+------------------------------------------------------------------+
void OnTrade()
{
    if(posTicket > 0)
    {
        if(!PositionSelectByTicket(posTicket))
        {
            posTicket = 0;
        }
    }

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol && 
           PositionGetInteger(POSITION_MAGIC) == Magic)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket != posTicket)
            {
                posTicket = ticket;
            }
        }
    }
} 
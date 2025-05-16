//+------------------------------------------------------------------+
//|                                                    SupertrendEA.mq5 |
//|                                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                           |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                       |
//+------------------------------------------------------------------+
enum ENUM_LOT_TYPE
{
    LOT_TYPE_FIXED = 0,    // Fixed lot size
    LOT_TYPE_RISK = 1      // Risk-based
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// Symbol and Magic
input group "=== Symbol and Magic ==="
input int      Magic = 548762;         // Magic Number

// Supertrend Settings
input group "=== Supertrend Settings ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe
input int    ATR_Period = 10;        // ATR Period
input double ATR_Multiplier = 14.0;   // ATR Multiplier

// ZigZag Settings
input group "=== ZigZag Settings ==="
input ENUM_TIMEFRAMES ZigZag_Timeframe = PERIOD_CURRENT;  // ZigZag Timeframe
input int    ZigZag_Depth = 12;      // Depth
input int    ZigZag_Deviation = 5;   // Deviation
input int    ZigZag_Backstep = 3;    // Backstep

// Trade Settings
input group "=== Trading Settings ==="
input ENUM_LOT_TYPE LotType = LOT_TYPE_RISK;  // Lot size type
input double LotSize = 1;          // Fixed lot size
input double RiskPercent = 1.0;      // Risk percentage per trade
input int      FixedTP = 0;       // Take Profit (points, 0=disabled)
input int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
input int      Buffer = 100;        // Order buffer (points)
input bool     CheckExistingPositions = true;  // Check existing positions

// Order Conditions
input group "=== Order Conditions ==="
input bool     EnableFirstBuyStop = false;     // Enable Buy Stop when Supertrend changes from bullish to bearish 
input bool     EnableSecondBuyStop = true;    // Enable Buy Stop after bullish Supertrend when a new ZigZag low forms
input bool     EnableFirstSellStop = false;    // Enable Sell Stop when Supertrend changes from bearish to bullish 
input bool     EnableSecondSellStop = true;   // Enable Sell Stop after bearish Supertrend when a new ZigZag high forms
input bool     UseZigZagForFirstBuyStop = true;  // Use ZigZag High for First Buy Stop (false = use Supertrend)
input bool     UseZigZagForFirstSellStop = true; // Use ZigZag Low for First Sell Stop (false = use Supertrend)

// RSI Partial Close Settings
input group "=== RSI Partial Close Settings ==="
input bool     EnableRSIPartialClose = false;    // Enable RSI partial close
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_CURRENT;  // RSI Timeframe
input int      RSI_Period = 14;                  // RSI Period
input double   RSI_UpperLevel = 70;             // RSI upper level for partial close
input double   RSI_LowerLevel = 30;             // RSI lower level for partial close
input double   PartialClosePercent = 33;        // Partial close percentage (0=disabled)
input int      MinProfitForPartialClose = 100;  // Minimum profit for partial close (points, 0=disabled)

// Trailing Stop
input group "=== Trailing Stop ==="
input int      TrailingStop = 0;   // Distance (points, 0=disabled)
input int      TrailingStep = 0;   // Step (points)

// Trade Limits
input group "=== Trading Limits ==="
input int      MaxDailyBuyTrades = 0;    // Max daily buy trades (0=unlimited)
input int      MaxDailySellTrades = 0;   // Max daily sell trades (0=unlimited)
input int      MaxDailyTrades = 0;       // Max total daily trades (0=unlimited)
input int      MaxBuyTrades = 0;         // Max buy trades (0=unlimited)
input int      MaxSellTrades = 0;        // Max sell trades (0=unlimited)
input int      MaxTrades = 0;            // Max total trades (0=unlimited)
input double   DailyTargetCurrency = 600.0;  // Daily Target (Currency, 0=disabled)
input double   DailyTargetPercent = 0.0;   // Daily Target (Percent, 0=disabled)
input double   DailyLossCurrency = 0.0;    // Daily Loss (Currency, 0=disabled)
input double   DailyLossPercent = 0.0;     // Daily Loss (Percent, 0=disabled)

// Trading Hours
input group "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input bool     AutoDetectBrokerOffset = false;  // Auto-detect GMT offset
input bool     BrokerIsAheadOfGMT = true;       // Broker ahead of GMT
input int      ManualBrokerOffset = 3;          // Manual GMT offset (hours)

// Spread and Slippage
input group "=== Spread and Slippage ==="
input int      MaxSpread =1000;         // Max spread (pips)
input int      Slippage = 3;           // Slippage (points)
input bool     CloseOnOppositeSupertrend = true;  // Close on trend change

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade trade;                         // Trading object
string CurrentSymbol;                 // Current symbol
int stHandle;                         // Supertrend indicator handle
int zzHandle;                         // ZigZag indicator handle
int rsiHandle;                        // RSI indicator handle
int totalBars;                        // Total number of bars
ulong posTicket;                      // Position ticket
double lotSize;                       // Lot size
bool tslActive;                       // Trailing stop loss active
double lastRSI;                       // Last RSI value
bool rsiPartialCloseDone;             // RSI partial close flag
double lastZigZagHigh = 0;           // Last ZigZag high
double lastZigZagLow = 0;            // Last ZigZag low
double previousZigZagHigh = 0;       // Previous ZigZag high
double previousZigZagLow = 0;        // Previous ZigZag low
bool isFirstSignalAfterBullish = false;  // First signal after bullish Supertrend
bool isFirstSignalAfterBearish = false;  // First signal after bearish Supertrend
double lastLowBeforeBullish = 0;     // First low after bullish trend
double lastHighBeforeBearish = 0;    // First high after bearish trend

// Ajout des variables globales pour le cache
double lastCalculatedProfit = 0.0;
datetime lastCalculationTime = 0;
int lastDealsCount = 0;
int lastPositionsCount = 0;
datetime lastBarTime = 0;  // Nouvelle variable pour suivre le dernier temps de bougie traité

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize current symbol
    CurrentSymbol = Symbol();
    
    // Check if symbol is valid
    if(!SymbolSelect(CurrentSymbol, true))
    {
        LogMessage("Error: Symbol " + CurrentSymbol + " not available");
        return(INIT_FAILED);
    }
    
    // Set trading parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(Slippage);
    
    // Check if enough bars are available
    if(iBars(CurrentSymbol, Timeframe) < ATR_Period + 1)
    {
        LogMessage("Error: Not enough bars for " + CurrentSymbol);
        return(INIT_FAILED);
    }
    
    // Initialize indicators
    stHandle = iCustom(CurrentSymbol, Timeframe, "SupertrendIndicator.ex5", ATR_Period, ATR_Multiplier);
    
    if(stHandle == INVALID_HANDLE)
    {
        LogMessage("Error initializing Supertrend indicator for " + CurrentSymbol + ". Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    zzHandle = iCustom(CurrentSymbol, ZigZag_Timeframe, "ZigZag.ex5", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
    
    if(zzHandle == INVALID_HANDLE)
    {
        LogMessage("Error initializing ZigZag indicator for " + CurrentSymbol + ". Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    // Initialize RSI if partial close is enabled
    if(EnableRSIPartialClose)
    {
        int attempt = 0;
        int maxAttempts = 10;
        while(attempt < maxAttempts)
        {
            rsiHandle = iRSI(CurrentSymbol, RSI_Timeframe, RSI_Period, PRICE_CLOSE);
            if(rsiHandle != INVALID_HANDLE)
                break;
            Sleep(1000); // Wait 1 second
            attempt++;
        }
        
        if(rsiHandle == INVALID_HANDLE)
        {
            LogMessage("Error initializing RSI indicator for " + CurrentSymbol);
            return(INIT_FAILED);
        }
    }
    
    // Add indicators to chart for synchronization
    if(!ChartIndicatorAdd(ChartID(), 0, stHandle))
    {
        LogMessage("Error: Cannot add Supertrend to chart");
        return(INIT_FAILED);
    }
    if(!ChartIndicatorAdd(ChartID(), 0, zzHandle))
    {
        LogMessage("Error: Cannot add ZigZag to chart");
        return(INIT_FAILED);
    }
    if(EnableRSIPartialClose && !ChartIndicatorAdd(ChartID(), 0, rsiHandle))
    {
        LogMessage("Error: Cannot add RSI to chart");
        return(INIT_FAILED);
    }
    
    
    totalBars = iBars(CurrentSymbol, Timeframe);
    lotSize = LotSize;
    tslActive = false;
    lastRSI = 0;
    rsiPartialCloseDone = false;
    lastBarTime = iTime(CurrentSymbol, Timeframe, 0);  // Initialisation du dernier temps de bougie
    
    // Enable timer for reliable bar detection
    EventSetTimer(1);
    
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
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop Loss                                          |
//+------------------------------------------------------------------+
void HandleTrailingStopLoss(double &st[])
{
    if(TrailingStop <= 0 || TrailingStep <= 0 || posTicket <= 0) return;
    
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
                    if(trade.PositionModify(posTicket, newSL, posTp))
                    {
                        // Suppression du log de modification du SL
                    }
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
                    if(trade.PositionModify(posTicket, newSL, posTp))
                    {
                        // Suppression du log de modification du SL
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
        
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickSize = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / tickSize;
    
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double stopLossPoints = MathAbs(entryPrice - stopLoss) / _Point;
    double takeProfitPoints = stopLossPoints * FixedTP / _Point;
    double totalRiskPoints = stopLossPoints + takeProfitPoints;
    
    double positionSize = NormalizeDouble(riskAmount / (totalRiskPoints * pointValue), 2);
    
    double minLot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
    
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    positionSize = NormalizeDouble(positionSize / lotStep, 0) * lotStep;
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    double currentSpread = (double)SymbolInfoInteger(CurrentSymbol, SYMBOL_SPREAD);
    return (currentSpread <= MaxSpread);
}

//+------------------------------------------------------------------+
//| Check trade limits                                                 |
//+------------------------------------------------------------------+
bool IsTradeAllowed(bool isBuy)
{
    if(MaxTrades > 0)
    {
        int totalTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && PositionGetInteger(POSITION_MAGIC) == Magic)
                totalTrades++;
        }
        if(totalTrades >= MaxTrades)
            return false;
    }
    
    if(isBuy && MaxBuyTrades > 0)
    {
        int buyTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                buyTrades++;
        }
        if(buyTrades >= MaxBuyTrades)
            return false;
    }
    else if(!isBuy && MaxSellTrades > 0)
    {
        int sellTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                sellTrades++;
        }
        if(sellTrades >= MaxSellTrades)
            return false;
    }
    
    if(MaxDailyTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailyTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic)
                dailyTrades++;
        }
        if(dailyTrades >= MaxDailyTrades)
            return false;
    }
    
    if(isBuy && MaxDailyBuyTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailyBuyTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY)
                dailyBuyTrades++;
        }
        if(dailyBuyTrades >= MaxDailyBuyTrades)
            return false;
    }
    else if(!isBuy && MaxDailySellTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailySellTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_SELL)
                dailySellTrades++;
        }
        if(dailySellTrades >= MaxDailySellTrades)
            return false;
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
            if(OrderGetString(ORDER_SYMBOL) == CurrentSymbol && 
               OrderGetInteger(ORDER_MAGIC) == Magic && 
               OrderGetInteger(ORDER_TYPE) == orderType)
            {
                trade.OrderDelete(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if position exists for symbol                                |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE posType)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
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
void HandleBuySignal(double &st[], double close1, double close2, double &zigzagHighLow[], double &zigzag[])
{
    if(CheckExistingPositions && HasPosition(POSITION_TYPE_BUY))
    {
        return;
    }

    if(!IsSpreadAcceptable())
    {
        return;
    }

    if(!IsTradeAllowed(true))
    {
        return;
    }

    if(close1 < st[1] && close2 > st[0])
    {
        isFirstSignalAfterBearish = true;
        isFirstSignalAfterBullish = false;

        double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

        double buyOrderPrice;
        if(UseZigZagForFirstBuyStop)
        {
            buyOrderPrice = lastZigZagHigh + Buffer * _Point;
        }
        else
        {
            buyOrderPrice = st[1] + Buffer * _Point;
        }
        buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);

        if(buyOrderPrice <= currentAsk)
        {
            buyOrderPrice = currentAsk + _Point;
            buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
        }

        if(buyOrderPrice <= 0 || (UseZigZagForFirstBuyStop && lastZigZagHigh <= 0))
        {
            return;
        }

        double sl = FixedSL > 0 ? NormalizeDouble(buyOrderPrice - FixedSL * _Point, _Digits) : 0;
        double tp = FixedTP > 0 ? NormalizeDouble(buyOrderPrice + FixedTP * _Point, _Digits) : 0;

        lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
        if(lotSize <= 0)
        {
            return;
        }

        DeletePendingOrders(ORDER_TYPE_BUY_STOP);

        datetime expiration = 0;
        if(trade.BuyStop(lotSize, buyOrderPrice, CurrentSymbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            posTicket = trade.ResultOrder();
            isFirstSignalAfterBullish = false;
            lastLowBeforeBullish = 0.0;
        }
        else
        {
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

                double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

                double buyOrderPrice = lastZigZagHigh + Buffer * _Point;
                buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);

                if(buyOrderPrice <= currentAsk)
                {
                    buyOrderPrice = currentAsk + _Point;
                    buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
                }

                double sl = FixedSL > 0 ? NormalizeDouble(buyOrderPrice - FixedSL * _Point, _Digits) : 0;
                double tp = FixedTP > 0 ? NormalizeDouble(buyOrderPrice + FixedTP * _Point, _Digits) : 0;

                lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
                if(lotSize <= 0)
                {
                    return;
                }

                DeletePendingOrders(ORDER_TYPE_BUY_STOP);

                datetime expiration = 0;
                if(trade.BuyStop(lotSize, buyOrderPrice, CurrentSymbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    posTicket = trade.ResultOrder();
                    isFirstSignalAfterBullish = false;
                    lastLowBeforeBullish = 0.0;
                }
                else
                {
                    isFirstSignalAfterBullish = false;
                    lastLowBeforeBullish = 0.0;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Sell Signal                                                 |
//+------------------------------------------------------------------+
void HandleSellSignal(double &st[], double close1, double close2, double &zigzagHighLow[], double &zigzag[])
{
    if(CheckExistingPositions && HasPosition(POSITION_TYPE_SELL))
    {
        return;
    }

    if(!IsSpreadAcceptable())
    {
        return;
    }

    if(!IsTradeAllowed(false))
    {
        return;
    }

    if(close1 > st[1] && close2 < st[0])
    {
        isFirstSignalAfterBullish = true;
        isFirstSignalAfterBearish = false;

        double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

        double sellOrderPrice;
        if(UseZigZagForFirstSellStop)
        {
            sellOrderPrice = lastZigZagLow - Buffer * _Point;
        }
        else
        {
            sellOrderPrice = st[1] - Buffer * _Point;
        }
        sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);

        if(sellOrderPrice >= currentBid)
        {
            sellOrderPrice = currentBid - _Point;
            sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
        }

        if(sellOrderPrice <= 0 || (UseZigZagForFirstSellStop && lastZigZagLow <= 0))
        {
            return;
        }

        double sl = FixedSL > 0 ? NormalizeDouble(sellOrderPrice + FixedSL * _Point, _Digits) : 0;
        double tp = FixedTP > 0 ? NormalizeDouble(sellOrderPrice - FixedTP * _Point, _Digits) : 0;

        lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
        if(lotSize <= 0)
        {
            return;
        }

        DeletePendingOrders(ORDER_TYPE_SELL_STOP);

        datetime expiration = 0;
        if(trade.SellStop(lotSize, sellOrderPrice, CurrentSymbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            posTicket = trade.ResultOrder();
            isFirstSignalAfterBearish = false;
            lastHighBeforeBearish = 0.0;
        }
        else
        {
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

                double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);

                double sellOrderPrice = lastZigZagLow - Buffer * _Point;
                sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);

                if(sellOrderPrice >= currentBid)
                {
                    sellOrderPrice = currentBid - _Point;
                    sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
                }

                double sl = FixedSL > 0 ? NormalizeDouble(sellOrderPrice + FixedSL * _Point, _Digits) : 0;
                double tp = FixedTP > 0 ? NormalizeDouble(sellOrderPrice - FixedTP * _Point, _Digits) : 0;

                lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
                if(lotSize <= 0)
                {
                    return;
                }

                DeletePendingOrders(ORDER_TYPE_SELL_STOP);

                datetime expiration = 0;
                if(trade.SellStop(lotSize, sellOrderPrice, CurrentSymbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    posTicket = trade.ResultOrder();
                    isFirstSignalAfterBearish = false;
                    lastHighBeforeBearish = 0.0;
                }
                else
                {
                    isFirstSignalAfterBearish = false;
                    lastHighBeforeBearish = 0.0;
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
    if(MQLInfoInteger(MQL_TESTER)) return true; // Autoriser trading en testeur
    datetime currentTime = TimeCurrent();
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
        return (currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes <= endTimeInMinutes);
    }
    
    return (currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes <= endTimeInMinutes);
}

//+------------------------------------------------------------------+
//| Check ZigZag Signal                                                |
//+------------------------------------------------------------------+
bool IsZigZagBuySignal(double &zigzag[], double &zigzagHighLow[])
{
    if(zigzagHighLow[1] == 0.0 && zigzagHighLow[0] != 0.0)
    {
        if(zigzag[0] > zigzag[1])
            return true;
    }
    return false;
}

bool IsZigZagSellSignal(double &zigzag[], double &zigzagHighLow[])
{
    if(zigzagHighLow[1] != 0.0 && zigzagHighLow[0] == 0.0)
    {
        if(zigzag[0] < zigzag[1])
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Handle RSI Partial Close                                           |
//+------------------------------------------------------------------+
void HandleRSIPartialClose()
{
    if(!EnableRSIPartialClose || PartialClosePercent <= 0 || MinProfitForPartialClose <= 0 || posTicket <= 0)
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
                // Suppression du log de fermeture partielle
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
                // Suppression du log de fermeture partielle
            }
        }
        else if(currentRSI > RSI_LowerLevel)
        {
            rsiPartialCloseDone = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Check if daily target or loss has been reached                     |
//+------------------------------------------------------------------+
bool IsDailyTargetReached()
{
    static double lastLoggedProfit = 0.0;
    static datetime lastLogTime = 0;
    
    if(DailyTargetCurrency <= 0.0 && DailyTargetPercent <= 0.0 && 
       DailyLossCurrency <= 0.0 && DailyLossPercent <= 0.0)
    {
        return false;
    }
    
    // Vérifier si on doit recalculer (toutes les 30 secondes ou si changement dans les positions/deals)
    datetime currentTime = TimeCurrent();
    int currentDealsCount = HistoryDealsTotal();
    int currentPositionsCount = PositionsTotal();
    
    bool shouldRecalculate = false;
    if(currentTime - lastCalculationTime >= 30)  // Recalcul toutes les 30 secondes
    {
        shouldRecalculate = true;
    }
    else if(currentDealsCount != lastDealsCount || currentPositionsCount != lastPositionsCount)
    {
        shouldRecalculate = true;
    }
    
    if(!shouldRecalculate)
    {
        return (DailyTargetCurrency > 0.0 && lastCalculatedProfit >= DailyTargetCurrency) ||
               (DailyTargetPercent > 0.0 && lastCalculatedProfit >= AccountInfoDouble(ACCOUNT_BALANCE) * DailyTargetPercent / 100.0) ||
               (DailyLossCurrency > 0.0 && lastCalculatedProfit <= -DailyLossCurrency) ||
               (DailyLossPercent > 0.0 && lastCalculatedProfit <= -AccountInfoDouble(ACCOUNT_BALANCE) * DailyLossPercent / 100.0);
    }
    
    // Mise à jour des compteurs
    lastCalculationTime = currentTime;
    lastDealsCount = currentDealsCount;
    lastPositionsCount = currentPositionsCount;
    
    datetime today = StringToTime(TimeToString(currentTime, TIME_DATE));
    double dailyProfit = 0.0;
    
    // Calcul du profit des trades fermés (optimisé)
    if(HistorySelect(today, currentTime))
    {
        for(int i = 0; i < currentDealsCount; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol)
            {
                dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            }
        }
    }
    
    // Calcul du profit des positions ouvertes (optimisé)
    for(int i = 0; i < currentPositionsCount; i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                dailyProfit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    
    // Mise à jour du cache
    lastCalculatedProfit = dailyProfit;
    
    // Vérification des cibles et des pertes
    if(DailyTargetCurrency > 0.0 && dailyProfit >= DailyTargetCurrency)
    {
        return true;
    }
    
    if(DailyTargetPercent > 0.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double targetAmount = accountBalance * DailyTargetPercent / 100.0;
        if(dailyProfit >= targetAmount)
        {
            return true;
        }
    }
    
    if(DailyLossCurrency > 0.0 && dailyProfit <= -DailyLossCurrency)
    {
        return true;
    }
    
    if(DailyLossPercent > 0.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double lossAmount = accountBalance * DailyLossPercent / 100.0;
        if(dailyProfit <= -lossAmount)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Tick function                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!IsWithinTradingHours())
        return;
        
    // Check if daily target or loss has been reached
    if(IsDailyTargetReached())
    {
        // Close all positions for this symbol
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
                   PositionGetInteger(POSITION_MAGIC) == Magic)
                {
                    trade.PositionClose(PositionGetTicket(i));
                }
            }
        }
        
        // Delete all pending orders for this symbol
        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            ulong ticket = OrderGetTicket(i);
            if(ticket > 0)
            {
                if(OrderGetString(ORDER_SYMBOL) == CurrentSymbol && 
                   OrderGetInteger(ORDER_MAGIC) == Magic)
                {
                    trade.OrderDelete(ticket);
                }
            }
        }
        return;
    }
    
    // Vérifier si une nouvelle bougie est formée
    datetime currentBarTime = iTime(CurrentSymbol, Timeframe, 0);
    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        totalBars = iBars(CurrentSymbol, Timeframe);
        
        double st[], zigzag[], zigzagHighLow[];
        ArrayResize(st, 3);
        ArrayResize(zigzag, 3);
        ArrayResize(zigzagHighLow, 3);
        ArraySetAsSeries(st, true);
        
        // Copy Supertrend buffer with retry
        int maxRetries = 5;
        int retryDelay = 100; // milliseconds
        int copied = 0;
        
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(stHandle, 0, 0, 3, st);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            LogMessage("Error copying Supertrend buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        // Copy ZigZag main buffer with retry
        copied = 0;
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(zzHandle, 0, 0, 3, zigzag);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            LogMessage("Error copying ZigZag buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        // Copy ZigZag HighLow buffer with retry
        copied = 0;
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(zzHandle, 1, 0, 3, zigzagHighLow);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            LogMessage("Error copying ZigZag HighLow buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        double close1 = iClose(CurrentSymbol, Timeframe, 1);
        double close2 = iClose(CurrentSymbol, Timeframe, 2);
        
        if(close1 == 0 || close2 == 0)
        {
            LogMessage("Error getting close prices");
            return;
        }
        
        HandleTrailingStopLoss(st);
        
        if(zigzagHighLow[0] != 0.0)
        {
            if(lastZigZagHigh != zigzag[0] && zigzag[0] != 0.0)
            {
                previousZigZagHigh = lastZigZagHigh;
                lastZigZagHigh = zigzag[0];
            }
        }
        else
        {
            if(lastZigZagLow != zigzag[0] && zigzag[0] != 0.0)
            {
                previousZigZagLow = lastZigZagLow;
                lastZigZagLow = zigzag[0];
            }
        }
        
        if(CloseOnOppositeSupertrend)
        {
            if(close1 < st[1] && close2 > st[0])
            {
                for(int j = PositionsTotal() - 1; j >= 0; j--)
                {
                    if(PositionSelectByTicket(PositionGetTicket(j)))
                    {
                        if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
                           PositionGetInteger(POSITION_MAGIC) == Magic &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                        {
                            trade.PositionClose(PositionGetTicket(j));
                        }
                    }
                }
            }
            
            if(close1 > st[1] && close2 < st[0])
            {
                for(int j = PositionsTotal() - 1; j >= 0; j--)
                {
                    if(PositionSelectByTicket(PositionGetTicket(j)))
                    {
                        if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
                           PositionGetInteger(POSITION_MAGIC) == Magic &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                        {
                            trade.PositionClose(PositionGetTicket(j));
                        }
                    }
                }
            }
        }
        
        HandleBuySignal(st, close1, close2, zigzagHighLow, zigzag);
        HandleSellSignal(st, close1, close2, zigzagHighLow, zigzag);
        
        if(EnableRSIPartialClose)
        {
            HandleRSIPartialClose();
        }
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
        if(PositionGetSymbol(i) == CurrentSymbol && 
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

//+------------------------------------------------------------------+
//| Log Management                                                     |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
    string log = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + " | " + message;
    Print(log);
    // Write to file for persistent debugging
    int handle = FileOpen("SupertrendEA_Log.txt", FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, log);
        FileClose(handle);
    }
}
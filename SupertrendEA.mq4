//+------------------------------------------------------------------+
//|                                                    SupertrendEA.mq4 |
//|                                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

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
extern int      Magic = 548762;         // Magic Number

// Supertrend Settings
extern ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe
extern int    ATR_Period = 10;        // ATR Period
extern double ATR_Multiplier = 14.0;   // ATR Multiplier

// ZigZag Settings
extern ENUM_TIMEFRAMES ZigZag_Timeframe = PERIOD_CURRENT;  // ZigZag Timeframe
extern int    ZigZag_Depth = 12;      // Depth
extern int    ZigZag_Deviation = 5;   // Deviation
extern int    ZigZag_Backstep = 3;    // Backstep

// Trade Settings
extern ENUM_LOT_TYPE LotType = LOT_TYPE_RISK;  // Lot size type
extern double LotSize = 1;          // Fixed lot size
extern double RiskPercent = 1.0;      // Risk percentage per trade
extern int      FixedTP = 0;       // Take Profit (points, 0=disabled)
extern int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
extern int      Buffer = 100;        // Order buffer (points)
extern bool     CheckExistingPositions = true;  // Check existing positions

// Order Conditions
extern bool     EnableFirstBuyStop = false;     // Enable Buy Stop when Supertrend changes from bullish to bearish 
extern bool     EnableSecondBuyStop = true;    // Enable Buy Stop after bullish Supertrend when a new ZigZag low forms
extern bool     EnableFirstSellStop = false;    // Enable Sell Stop when Supertrend changes from bearish to bullish 
extern bool     EnableSecondSellStop = true;   // Enable Sell Stop after bearish Supertrend when a new ZigZag high forms
extern bool     UseZigZagForFirstBuyStop = true;  // Use ZigZag High for First Buy Stop (false = use Supertrend)
extern bool     UseZigZagForFirstSellStop = true; // Use ZigZag Low for First Sell Stop (false = use Supertrend)

// RSI Partial Close Settings
extern bool     EnableRSIPartialClose = false;    // Enable RSI partial close
extern ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_CURRENT;  // RSI Timeframe
extern int      RSI_Period = 14;                  // RSI Period
extern double   RSI_UpperLevel = 70;             // RSI upper level for partial close
extern double   RSI_LowerLevel = 30;             // RSI lower level for partial close
extern double   PartialClosePercent = 33;        // Partial close percentage (0=disabled)
extern int      MinProfitForPartialClose = 100;  // Minimum profit for partial close (points, 0=disabled)

// Trailing Stop
extern int      TrailingStop = 0;   // Distance (points, 0=disabled)
extern int      TrailingStep = 0;   // Step (points)

// Trade Limits
extern int      MaxDailyBuyTrades = 0;    // Max daily buy trades (0=unlimited)
extern int      MaxDailySellTrades = 0;   // Max daily sell trades (0=unlimited)
extern int      MaxDailyTrades = 0;       // Max total daily trades (0=unlimited)
extern int      MaxBuyTrades = 0;         // Max buy trades (0=unlimited)
extern int      MaxSellTrades = 0;        // Max sell trades (0=unlimited)
extern int      MaxTrades = 0;            // Max total trades (0=unlimited)
extern double   DailyTargetCurrency = 600.0;  // Daily Target (Currency, 0=disabled)
extern double   DailyTargetPercent = 0.0;   // Daily Target (Percent, 0=disabled)
extern double   DailyLossCurrency = 0.0;    // Daily Loss (Currency, 0=disabled)
extern double   DailyLossPercent = 0.0;     // Daily Loss (Percent, 0=disabled)

// Trading Hours
extern int      TimeStartHour = 0;      // Start hour
extern int      TimeStartMinute = 0;    // Start minute
extern int      TimeEndHour = 23;       // End hour
extern int      TimeEndMinute = 59;     // End minute
extern bool     AutoDetectBrokerOffset = false;  // Auto-detect GMT offset
extern bool     BrokerIsAheadOfGMT = true;       // Broker ahead of GMT
extern int      ManualBrokerOffset = 3;          // Manual GMT offset (hours)

// Spread and Slippage
extern int      MaxSpread = 1000;         // Max spread (pips)
extern int      Slippage = 3;           // Slippage (points)
extern bool     CloseOnOppositeSupertrend = true;  // Close on trend change

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
string CurrentSymbol;                 // Current symbol
int stHandle;                         // Supertrend indicator handle
int zzHandle;                         // ZigZag indicator handle
int rsiHandle;                        // RSI indicator handle
int totalBars;                        // Total number of bars
int posTicket;                        // Position ticket
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

// Cache variables
double lastCalculatedProfit = 0.0;
datetime lastCalculationTime = 0;
int lastDealsCount = 0;
int lastPositionsCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int init()
{
    // Initialize current symbol
    CurrentSymbol = Symbol();
    
    // Check if symbol is valid
    if(!MarketInfo(CurrentSymbol, MODE_TRADEALLOWED))
    {
        LogMessage("Error: Symbol " + CurrentSymbol + " not available");
        return(INIT_FAILED);
    }
    
    // Check if enough bars are available
    if(Bars < ATR_Period + 1)
    {
        LogMessage("Error: Not enough bars for " + CurrentSymbol);
        return(INIT_FAILED);
    }
    
    // Initialize indicators
    stHandle = iCustom(CurrentSymbol, Timeframe, "SupertrendIndicator", ATR_Period, ATR_Multiplier);
    
    if(stHandle == INVALID_HANDLE)
    {
        LogMessage("Error initializing Supertrend indicator for " + CurrentSymbol + ". Error code: " + GetLastError());
        return(INIT_FAILED);
    }
    
    zzHandle = iCustom(CurrentSymbol, ZigZag_Timeframe, "ZigZag", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep);
    
    if(zzHandle == INVALID_HANDLE)
    {
        LogMessage("Error initializing ZigZag indicator for " + CurrentSymbol + ". Error code: " + GetLastError());
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
    
    totalBars = Bars;
    lotSize = LotSize;
    tslActive = false;
    lastRSI = 0;
    rsiPartialCloseDone = false;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void deinit()
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
void HandleTrailingStopLoss(double &st[])
{
    if(TrailingStop <= 0 || TrailingStep <= 0 || posTicket <= 0) return;
    
    if(OrderSelect(posTicket, SELECT_BY_TICKET))
    {
        double currentPrice = MarketInfo(OrderSymbol(), MODE_BID);
        double openPrice = OrderOpenPrice();
        double currentSL = OrderStopLoss();
        double posTp = OrderTakeProfit();
        
        if(OrderType() == OP_BUY)
        {
            double profitPoints = (currentPrice - openPrice) / Point;
            if(profitPoints >= TrailingStop)
            {
                double newSL = currentPrice - TrailingStep * Point;
                if(newSL > currentSL || currentSL == 0)
                {
                    if(OrderModify(OrderTicket(), openPrice, newSL, posTp, 0, clrNone))
                    {
                        // Trailing stop modified
                    }
                }
            }
        }
        else if(OrderType() == OP_SELL)
        {
            double profitPoints = (openPrice - currentPrice) / Point;
            if(profitPoints >= TrailingStop)
            {
                double newSL = currentPrice + TrailingStep * Point;
                if(newSL < currentSL || currentSL == 0)
                {
                    if(OrderModify(OrderTicket(), openPrice, newSL, posTp, 0, clrNone))
                    {
                        // Trailing stop modified
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
        
    double accountBalance = AccountBalance();
    double tickSize = MarketInfo(CurrentSymbol, MODE_TICKSIZE);
    double tickValue = MarketInfo(CurrentSymbol, MODE_TICKVALUE);
    double pointValue = tickValue / tickSize;
    
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double stopLossPoints = MathAbs(entryPrice - stopLoss) / Point;
    double takeProfitPoints = stopLossPoints * FixedTP / Point;
    double totalRiskPoints = stopLossPoints + takeProfitPoints;
    
    double positionSize = NormalizeDouble(riskAmount / (totalRiskPoints * pointValue), 2);
    
    double minLot = MarketInfo(CurrentSymbol, MODE_MINLOT);
    double maxLot = MarketInfo(CurrentSymbol, MODE_MAXLOT);
    double lotStep = MarketInfo(CurrentSymbol, MODE_LOTSTEP);
    
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    positionSize = NormalizeDouble(positionSize / lotStep, 0) * lotStep;
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
    double currentSpread = MarketInfo(CurrentSymbol, MODE_SPREAD);
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
        for(int i = 0; i < OrdersTotal(); i++)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderSymbol() == CurrentSymbol && OrderMagicNumber() == Magic)
                    totalTrades++;
            }
        }
        if(totalTrades >= MaxTrades)
            return false;
    }
    
    if(isBuy && MaxBuyTrades > 0)
    {
        int buyTrades = 0;
        for(int i = 0; i < OrdersTotal(); i++)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderSymbol() == CurrentSymbol && 
                   OrderMagicNumber() == Magic &&
                   OrderType() == OP_BUY)
                    buyTrades++;
            }
        }
        if(buyTrades >= MaxBuyTrades)
            return false;
    }
    else if(!isBuy && MaxSellTrades > 0)
    {
        int sellTrades = 0;
        for(int i = 0; i < OrdersTotal(); i++)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderSymbol() == CurrentSymbol && 
                   OrderMagicNumber() == Magic &&
                   OrderType() == OP_SELL)
                    sellTrades++;
            }
        }
        if(sellTrades >= MaxSellTrades)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Delete all pending orders of specified type                        |
//+------------------------------------------------------------------+
void DeletePendingOrders(int orderType)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == CurrentSymbol && 
               OrderMagicNumber() == Magic && 
               OrderType() == orderType)
            {
                OrderDelete(OrderTicket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if position exists for symbol                                |
//+------------------------------------------------------------------+
bool HasPosition(int posType)
{
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == CurrentSymbol && 
               OrderMagicNumber() == Magic &&
               OrderType() == posType)
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
    if(CheckExistingPositions && HasPosition(OP_BUY))
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

        double currentBid = MarketInfo(CurrentSymbol, MODE_BID);
        double currentAsk = MarketInfo(CurrentSymbol, MODE_ASK);

        double buyOrderPrice;
        if(UseZigZagForFirstBuyStop)
        {
            buyOrderPrice = lastZigZagHigh + Buffer * Point;
        }
        else
        {
            buyOrderPrice = st[1] + Buffer * Point;
        }
        buyOrderPrice = NormalizeDouble(buyOrderPrice, Digits);

        if(buyOrderPrice <= currentAsk)
        {
            buyOrderPrice = currentAsk + Point;
            buyOrderPrice = NormalizeDouble(buyOrderPrice, Digits);
        }

        if(buyOrderPrice <= 0 || (UseZigZagForFirstBuyStop && lastZigZagHigh <= 0))
        {
            return;
        }

        double sl = FixedSL > 0 ? NormalizeDouble(buyOrderPrice - FixedSL * Point, Digits) : 0;
        double tp = FixedTP > 0 ? NormalizeDouble(buyOrderPrice + FixedTP * Point, Digits) : 0;

        lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
        if(lotSize <= 0)
        {
            return;
        }

        DeletePendingOrders(OP_BUYSTOP);

        int ticket = OrderSend(CurrentSymbol, OP_BUYSTOP, lotSize, buyOrderPrice, Slippage, sl, tp, "", Magic, 0, clrNone);
        if(ticket > 0)
        {
            posTicket = ticket;
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

                double currentBid = MarketInfo(CurrentSymbol, MODE_BID);
                double currentAsk = MarketInfo(CurrentSymbol, MODE_ASK);

                double buyOrderPrice = lastZigZagHigh + Buffer * Point;
                buyOrderPrice = NormalizeDouble(buyOrderPrice, Digits);

                if(buyOrderPrice <= currentAsk)
                {
                    buyOrderPrice = currentAsk + Point;
                    buyOrderPrice = NormalizeDouble(buyOrderPrice, Digits);
                }

                double sl = FixedSL > 0 ? NormalizeDouble(buyOrderPrice - FixedSL * Point, Digits) : 0;
                double tp = FixedTP > 0 ? NormalizeDouble(buyOrderPrice + FixedTP * Point, Digits) : 0;

                lotSize = CalculatePositionSize(sl, buyOrderPrice, true);
                if(lotSize <= 0)
                {
                    return;
                }

                DeletePendingOrders(OP_BUYSTOP);

                int ticket = OrderSend(CurrentSymbol, OP_BUYSTOP, lotSize, buyOrderPrice, Slippage, sl, tp, "", Magic, 0, clrNone);
                if(ticket > 0)
                {
                    posTicket = ticket;
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
    if(CheckExistingPositions && HasPosition(OP_SELL))
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

        double currentBid = MarketInfo(CurrentSymbol, MODE_BID);
        double currentAsk = MarketInfo(CurrentSymbol, MODE_ASK);

        double sellOrderPrice;
        if(UseZigZagForFirstSellStop)
        {
            sellOrderPrice = lastZigZagLow - Buffer * Point;
        }
        else
        {
            sellOrderPrice = st[1] - Buffer * Point;
        }
        sellOrderPrice = NormalizeDouble(sellOrderPrice, Digits);

        if(sellOrderPrice >= currentBid)
        {
            sellOrderPrice = currentBid - Point;
            sellOrderPrice = NormalizeDouble(sellOrderPrice, Digits);
        }

        if(sellOrderPrice <= 0 || (UseZigZagForFirstSellStop && lastZigZagLow <= 0))
        {
            return;
        }

        double sl = FixedSL > 0 ? NormalizeDouble(sellOrderPrice + FixedSL * Point, Digits) : 0;
        double tp = FixedTP > 0 ? NormalizeDouble(sellOrderPrice - FixedTP * Point, Digits) : 0;

        lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
        if(lotSize <= 0)
        {
            return;
        }

        DeletePendingOrders(OP_SELLSTOP);

        int ticket = OrderSend(CurrentSymbol, OP_SELLSTOP, lotSize, sellOrderPrice, Slippage, sl, tp, "", Magic, 0, clrNone);
        if(ticket > 0)
        {
            posTicket = ticket;
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

                double currentBid = MarketInfo(CurrentSymbol, MODE_BID);
                double currentAsk = MarketInfo(CurrentSymbol, MODE_ASK);

                double sellOrderPrice = lastZigZagLow - Buffer * Point;
                sellOrderPrice = NormalizeDouble(sellOrderPrice, Digits);

                if(sellOrderPrice >= currentBid)
                {
                    sellOrderPrice = currentBid - Point;
                    sellOrderPrice = NormalizeDouble(sellOrderPrice, Digits);
                }

                double sl = FixedSL > 0 ? NormalizeDouble(sellOrderPrice + FixedSL * Point, Digits) : 0;
                double tp = FixedTP > 0 ? NormalizeDouble(sellOrderPrice - FixedTP * Point, Digits) : 0;

                lotSize = CalculatePositionSize(sl, sellOrderPrice, false);
                if(lotSize <= 0)
                {
                    return;
                }

                DeletePendingOrders(OP_SELLSTOP);

                int ticket = OrderSend(CurrentSymbol, OP_SELLSTOP, lotSize, sellOrderPrice, Slippage, sl, tp, "", Magic, 0, clrNone);
                if(ticket > 0)
                {
                    posTicket = ticket;
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
    if(IsTesting()) return true; // Allow trading in tester
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
        
    if(!OrderSelect(posTicket, SELECT_BY_TICKET))
        return;
        
    double rsi[];
    ArraySetAsSeries(rsi, true);
    if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) <= 0)
        return;
        
    double currentRSI = rsi[0];
    double previousRSI = lastRSI;
    lastRSI = currentRSI;
    
    double openPrice = OrderOpenPrice();
    double currentPrice = OrderType() == OP_BUY ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
    double positionVolume = OrderLots();
    int posType = OrderType();
    
    double profitPoints = 0;
    if(posType == OP_BUY)
        profitPoints = (currentPrice - openPrice) / Point;
    else if(posType == OP_SELL)
        profitPoints = (openPrice - currentPrice) / Point;
        
    if(profitPoints < MinProfitForPartialClose)
        return;
        
    if(posType == OP_BUY)
    {
        if(previousRSI < RSI_UpperLevel && currentRSI > RSI_UpperLevel && !rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(OrderClose(OrderTicket(), closeVolume, MarketInfo(OrderSymbol(), MODE_BID), Slippage, clrNone))
            {
                // Partial close successful
            }
        }
        else if(currentRSI < RSI_UpperLevel)
        {
            rsiPartialCloseDone = false;
        }
    }
    else if(posType == OP_SELL)
    {
        if(previousRSI > RSI_LowerLevel && currentRSI < RSI_LowerLevel && !rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(OrderClose(OrderTicket(), closeVolume, MarketInfo(OrderSymbol(), MODE_ASK), Slippage, clrNone))
            {
                // Partial close successful
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
    
    // Check if we should recalculate (every 30 seconds or if positions/deals changed)
    datetime currentTime = TimeCurrent();
    int currentDealsCount = OrdersHistoryTotal();
    int currentPositionsCount = OrdersTotal();
    
    bool shouldRecalculate = false;
    if(currentTime - lastCalculationTime >= 30)  // Recalculate every 30 seconds
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
               (DailyTargetPercent > 0.0 && lastCalculatedProfit >= AccountBalance() * DailyTargetPercent / 100.0) ||
               (DailyLossCurrency > 0.0 && lastCalculatedProfit <= -DailyLossCurrency) ||
               (DailyLossPercent > 0.0 && lastCalculatedProfit <= -AccountBalance() * DailyLossPercent / 100.0);
    }
    
    // Update counters
    lastCalculationTime = currentTime;
    lastDealsCount = currentDealsCount;
    lastPositionsCount = currentPositionsCount;
    
    datetime today = StringToTime(TimeToString(currentTime, TIME_DATE));
    double dailyProfit = 0.0;
    
    // Calculate profit from closed trades
    for(int i = 0; i < OrdersHistoryTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == Magic &&
               OrderSymbol() == CurrentSymbol)
            {
                dailyProfit += OrderProfit();
            }
        }
    }
    
    // Calculate profit from open positions
    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == CurrentSymbol && 
               OrderMagicNumber() == Magic)
            {
                dailyProfit += OrderProfit();
            }
        }
    }
    
    // Update cache
    lastCalculatedProfit = dailyProfit;
    
    // Check targets and losses
    if(DailyTargetCurrency > 0.0 && dailyProfit >= DailyTargetCurrency)
    {
        return true;
    }
    
    if(DailyTargetPercent > 0.0)
    {
        double accountBalance = AccountBalance();
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
        double accountBalance = AccountBalance();
        double lossAmount = accountBalance * DailyLossPercent / 100.0;
        if(dailyProfit <= -lossAmount)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Expert start function                                              |
//+------------------------------------------------------------------+
void start()
{
    if(!IsWithinTradingHours())
        return;
        
    // Check if daily target or loss has been reached
    if(IsDailyTargetReached())
    {
        // Close all positions for this symbol
        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderSymbol() == CurrentSymbol && 
                   OrderMagicNumber() == Magic)
                {
                    if(OrderType() == OP_BUY)
                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), Slippage, clrNone);
                    else if(OrderType() == OP_SELL)
                        OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), Slippage, clrNone);
                }
            }
        }
        
        // Delete all pending orders for this symbol
        for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            {
                if(OrderSymbol() == CurrentSymbol && 
                   OrderMagicNumber() == Magic)
                {
                    OrderDelete(OrderTicket());
                }
            }
        }
        return;
    }
    
    int bars = Bars;
    if(totalBars != bars)
    {
        totalBars = bars;
        
        double st[], zigzag[], zigzagHighLow[];
        ArrayResize(st, 3);
        ArrayResize(zigzag, 3);
        ArrayResize(zigzagHighLow, 3);
        ArraySetAsSeries(st, true);
        
        // Copy Supertrend buffer
        for(int i = 0; i < 3; i++)
        {
            st[i] = iCustom(CurrentSymbol, Timeframe, "SupertrendIndicator", ATR_Period, ATR_Multiplier, 0, i);
        }
        
        // Copy ZigZag main buffer
        for(int i = 0; i < 3; i++)
        {
            zigzag[i] = iCustom(CurrentSymbol, ZigZag_Timeframe, "ZigZag", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep, 0, i);
        }
        
        // Copy ZigZag HighLow buffer
        for(int i = 0; i < 3; i++)
        {
            zigzagHighLow[i] = iCustom(CurrentSymbol, ZigZag_Timeframe, "ZigZag", ZigZag_Depth, ZigZag_Deviation, ZigZag_Backstep, 1, i);
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
                for(int j = OrdersTotal() - 1; j >= 0; j--)
                {
                    if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
                    {
                        if(OrderSymbol() == CurrentSymbol && 
                           OrderMagicNumber() == Magic &&
                           OrderType() == OP_BUY)
                        {
                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), Slippage, clrNone);
                        }
                    }
                }
            }
            
            if(close1 > st[1] && close2 < st[0])
            {
                for(int j = OrdersTotal() - 1; j >= 0; j--)
                {
                    if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
                    {
                        if(OrderSymbol() == CurrentSymbol && 
                           OrderMagicNumber() == Magic &&
                           OrderType() == OP_SELL)
                        {
                            OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), Slippage, clrNone);
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
//| Log Management                                                     |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
    string log = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + " | " + message;
    Print(log);
    // Write to file for persistent debugging
    int handle = FileOpen("SupertrendEA_Log.txt", FILE_WRITE|FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, log);
        FileClose(handle);
    }
} 
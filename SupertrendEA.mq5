//+------------------------------------------------------------------+
//|                                                    SupertrendEA.mq5 |
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
//| Structures                                                         |
//+------------------------------------------------------------------+
struct TradingPair
{
    string symbol;           // Symbol name
    int stHandle;           // Supertrend indicator handle
    int zzHandle;           // ZigZag indicator handle
    int rsiHandle;          // RSI indicator handle
    int totalBars;          // Total number of bars
    ulong posTicket;        // Position ticket
    double lotSize;         // Lot size for this pair
    bool tslActive;         // Trailing stop loss active
    int atrPeriod;          // ATR Period
    double atrMultiplier;   // ATR Multiplier
    int zzDepth;           // ZigZag Depth
    int zzDeviation;       // ZigZag Deviation
    int zzBackstep;        // ZigZag Backstep
    double lastRSI;        // Last RSI value
    bool rsiPartialCloseDone;  // Flag for RSI partial close
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// Pairs and Magic
input group "=== Pairs and Magic ==="
input string TradingPairs = "XAUUSD,EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,NZDUSD,EURJPY,GBPJPY,EURGBP,USDCHF";  // Trading Pairs
input int      Magic = 548762;         // Magic Number

// Supertrend Settings
input group "=== Supertrend Settings ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe
input int    ATR_Period = 10;        // ATR Period
input double ATR_Multiplier = 3.0;   // ATR Multiplier

// ZigZag Settings
input group "=== ZigZag Settings ==="
input int    ZigZag_Depth = 12;      // Depth
input int    ZigZag_Deviation = 5;   // Deviation
input int    ZigZag_Backstep = 3;    // Backstep

// Trade Settings
input group "=== Trade Settings ==="
input ENUM_LOT_TYPE LotType = LOT_TYPE_FIXED;  // Lot Size Type
input double LotSize = 1;          // Fixed Lot Size
input double RiskPercent = 1.0;      // Risk % per Trade
input int      FixedTP = 0;       // Take Profit (points, 0=disabled)
input int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
input int      Buffer = 100;        // Order Buffer (points)
input bool     CheckExistingPositions = true;  // Check Existing Positions

// RSI Partial Close Settings
input group "=== RSI Partial Close Settings ==="
input bool     EnableRSIPartialClose = true;    // Enable RSI Partial Close
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_CURRENT;  // RSI Timeframe
input int      RSI_Period = 14;                  // RSI Period
input double   RSI_UpperLevel = 70;             // RSI Upper Level for Partial Close
input double   RSI_LowerLevel = 30;             // RSI Lower Level for Partial Close
input double   PartialClosePercent = 33;        // Partial Close Percentage (0=disabled)
input int      MinProfitForPartialClose = 100;  // Min Profit for Partial Close (points, 0=disabled)

// Trailing Stop
input group "=== Trailing Stop ==="
input int      TrailingStop = 0;   // Distance (points, 0=disabled)
input int      TrailingStep = 0;   // Step (points)

// Trade Limits
input group "=== Trade Limits ==="
input int      MaxDailyBuyTradesPerPair = 0;    // Max Daily Buy per Pair (0=unlimited)
input int      MaxDailySellTradesPerPair = 0;   // Max Daily Sell per Pair (0=unlimited)
input int      MaxDailyTradesOnAccount = 0;     // Max Daily Trades (0=unlimited)
input int      MaxBuyTradesPerPair = 0;         // Max Buy per Pair (0=unlimited)
input int      MaxSellTradesPerPair = 0;        // Max Sell per Pair (0=unlimited)
input int      MaxTradesOnAccount = 0;          // Max Total Trades (0=unlimited)

// Trading Hours
input group "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Start Hour
input int      TimeStartMinute = 0;    // Start Minute
input int      TimeEndHour = 23;       // End Hour
input int      TimeEndMinute = 59;     // End Minute
input bool     AutoDetectBrokerOffset = false;  // Auto Detect GMT Offset
input bool     BrokerIsAheadOfGMT = true;       // Broker Ahead of GMT
input int      ManualBrokerOffset = 3;          // Manual GMT Offset (hours)

// Spread and Slippage
input group "=== Spread and Slippage ==="
input int      MaxSpread = 40;         // Max Spread (pips)
input int      Slippage = 3;           // Slippage (points)
input bool     CloseOnOppositeSupertrend = true;  // Close on Trend Change

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
TradingPair pairs[];                  // Array of trading pairs
CTrade trade;                         // Trading object
double lastZigZagHigh = 0;           // Last ZigZag high value
double lastZigZagLow = 0;            // Last ZigZag low value
double previousZigZagHigh = 0;       // Previous ZigZag high value
double previousZigZagLow = 0;        // Previous ZigZag low value
bool isFirstSignalAfterBullish = false;  // Flag for first signal after bullish Supertrend
bool isFirstSignalAfterBearish = false;  // Flag for first signal after bearish Supertrend
double lastLowBeforeBullish = 0;  // Pour le premier Low après tendance haussière
double lastHighBeforeBearish = 0; // Pour le premier High après tendance baissière

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(Slippage);
    
    // Split trading pairs string into array
    string pairsStr[];
    StringSplit(TradingPairs, ',', pairsStr);
    
    // Initialize array size
    ArrayResize(pairs, ArraySize(pairsStr));
    
    // Initialize each trading pair
    for(int i = 0; i < ArraySize(pairs); i++)
    {
        string symbol = pairsStr[i];
        StringTrimRight(symbol);
        StringTrimLeft(symbol);
        pairs[i].symbol = symbol;
        
        pairs[i].lotSize = LotSize;
        pairs[i].tslActive = false;
        pairs[i].atrPeriod = ATR_Period;
        pairs[i].atrMultiplier = ATR_Multiplier;
        pairs[i].zzDepth = ZigZag_Depth;
        pairs[i].zzDeviation = ZigZag_Deviation;
        pairs[i].zzBackstep = ZigZag_Backstep;
        
        // Initialize indicators
        pairs[i].totalBars = iBars(pairs[i].symbol, Timeframe);
        pairs[i].stHandle = iCustom(pairs[i].symbol, Timeframe, "Supertrend.ex5", 
                                  pairs[i].atrPeriod, pairs[i].atrMultiplier);
        pairs[i].zzHandle = iCustom(pairs[i].symbol, Timeframe, "ZigZag.ex5",
                                  pairs[i].zzDepth, pairs[i].zzDeviation, pairs[i].zzBackstep);
        
        if(pairs[i].stHandle == INVALID_HANDLE)
        {
            Print("Error initializing Supertrend indicator for ", pairs[i].symbol);
            return(INIT_FAILED);
        }
        
        if(pairs[i].zzHandle == INVALID_HANDLE)
        {
            Print("Error initializing ZigZag indicator for ", pairs[i].symbol);
            return(INIT_FAILED);
        }
        
        // Initialize RSI indicator if partial close is enabled
        if(EnableRSIPartialClose)
        {
            int attempt = 0;
            int maxAttempts = 10; // Added for the new RSI_Timeframe parameter
            while(attempt < maxAttempts)
            {
                pairs[i].rsiHandle = iRSI(pairs[i].symbol, RSI_Timeframe, RSI_Period, PRICE_CLOSE);
                if(pairs[i].rsiHandle != INVALID_HANDLE)
                    break;
                Sleep(1000); // Attendre 1 seconde avant de réessayer
                attempt++;
            }
            
            if(pairs[i].rsiHandle == INVALID_HANDLE)
            {
                Print("Error initializing RSI indicator for ", pairs[i].symbol, " after ", maxAttempts, " attempts");
                return(INIT_FAILED);
            }
        }
        
        pairs[i].lastRSI = 0;
        pairs[i].rsiPartialCloseDone = false;
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    for(int i = 0; i < ArraySize(pairs); i++)
    {
        if(pairs[i].stHandle != INVALID_HANDLE)
            IndicatorRelease(pairs[i].stHandle);
        if(pairs[i].zzHandle != INVALID_HANDLE)
            IndicatorRelease(pairs[i].zzHandle);
        if(pairs[i].rsiHandle != INVALID_HANDLE)
            IndicatorRelease(pairs[i].rsiHandle);
    }
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop Loss                                          |
//+------------------------------------------------------------------+
void HandleTrailingStopLoss(TradingPair &pair, double &st[])
{
    if(TrailingStop <= 0 || TrailingStep <= 0) return;
    
    if(pair.posTicket > 0)
    {
        if(PositionSelectByTicket(pair.posTicket))
        {
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double posTp = PositionGetDouble(POSITION_TP);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
            {
                // Calculer le profit en points
                double profitPoints = (currentPrice - openPrice) / _Point;
                
                // Si le profit dépasse TrailingStop, activer le trailing
                if(profitPoints >= TrailingStop)
                {
                    double newSL = currentPrice - TrailingStep * _Point;
                    // Ne modifier le SL que s'il est plus haut que l'ancien
                    if(newSL > currentSL || currentSL == 0)
                    {
                        if(trade.PositionModify(pair.posTicket, newSL, posTp))
                        {
                            Print(__FUNCTION__, " > Buy position #", pair.posTicket, " SL modified to ", newSL);
                        }
                    }
                }
            } 
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) 
            {
                // Calculer le profit en points
                double profitPoints = (openPrice - currentPrice) / _Point;
                
                // Si le profit dépasse TrailingStop, activer le trailing
                if(profitPoints >= TrailingStop)
                {
                    double newSL = currentPrice + TrailingStep * _Point;
                    // Ne modifier le SL que s'il est plus bas que l'ancien
                    if(newSL < currentSL || currentSL == 0)
                    {
                        if(trade.PositionModify(pair.posTicket, newSL, posTp))
                        {
                            Print(__FUNCTION__, " > Sell position #", pair.posTicket, " SL modified to ", newSL);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Position Size                                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double stopLoss, double entryPrice, bool isBuy)
{
    if(LotType == LOT_TYPE_FIXED)
        return LotSize;
        
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double pointValue = tickValue / tickSize;
    
    // Calculate risk amount based on account balance and risk percentage
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    // Calculate stop loss distance in points
    double stopLossPoints = MathAbs(entryPrice - stopLoss) / _Point;
    
    // Calculate take profit distance based on TPFactor
    double takeProfitPoints = stopLossPoints * FixedTP / _Point;
    
    // Calculate total risk (SL + TP) in points
    double totalRiskPoints = stopLossPoints + takeProfitPoints;
    
    // Calculate position size based on total risk
    double positionSize = NormalizeDouble(riskAmount / (totalRiskPoints * pointValue), 2);
    
    // Apply lot size limits
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
    positionSize = NormalizeDouble(positionSize / lotStep, 0) * lotStep;
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                      |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(string symbol)
{
    double currentSpread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    return (currentSpread <= MaxSpread);
}

//+------------------------------------------------------------------+
//| Check trade limits                                                 |
//+------------------------------------------------------------------+
bool IsTradeAllowed(string symbol, bool isBuy)
{
    // Check total trades on account
    if(MaxTradesOnAccount > 0)
    {
        int totalTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == symbol && PositionGetInteger(POSITION_MAGIC) == Magic)
                totalTrades++;
        }
        if(totalTrades >= MaxTradesOnAccount)
            return false;
    }
    
    // Check trades per pair
    if(isBuy && MaxBuyTradesPerPair > 0)
    {
        int buyTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                buyTrades++;
        }
        if(buyTrades >= MaxBuyTradesPerPair)
            return false;
    }
    else if(!isBuy && MaxSellTradesPerPair > 0)
    {
        int sellTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                sellTrades++;
        }
        if(sellTrades >= MaxSellTradesPerPair)
            return false;
    }
    
    // Check daily trades on account
    if(MaxDailyTradesOnAccount > 0)
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
        if(dailyTrades >= MaxDailyTradesOnAccount)
            return false;
    }
    
    // Check daily trades per pair
    if(isBuy && MaxDailyBuyTradesPerPair > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailyBuyTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY)
                dailyBuyTrades++;
        }
        if(dailyBuyTrades >= MaxDailyBuyTradesPerPair)
            return false;
    }
    else if(!isBuy && MaxDailySellTradesPerPair > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailySellTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_SELL)
                dailySellTrades++;
        }
        if(dailySellTrades >= MaxDailySellTradesPerPair)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Delete all pending orders of specified type                        |
//+------------------------------------------------------------------+
void DeletePendingOrders(string symbol, ENUM_ORDER_TYPE orderType)
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0)
        {
            if(OrderGetString(ORDER_SYMBOL) == symbol && 
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
bool HasPosition(string symbol, ENUM_POSITION_TYPE posType)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
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
void HandleBuySignal(TradingPair &pair, double &st[], double close1, double close2, double &zigzagHighLow[], double &zigzag[])
{
    // Vérifier si une position d'achat existe déjà si l'option est activée
    if(CheckExistingPositions && HasPosition(pair.symbol, POSITION_TYPE_BUY))
    {
        Print(__FUNCTION__, " > Buy position already exists for ", pair.symbol);
        return;
    }

    // Check for Supertrend direction change to bearish
    if(close1 < st[1] && close2 > st[0])
    {
        isFirstSignalAfterBearish = true;
        isFirstSignalAfterBullish = false;
        
        Print(__FUNCTION__, " > Supertrend turned bearish for ", pair.symbol);
        
        if(!IsSpreadAcceptable(pair.symbol))
        {
            Print(__FUNCTION__, " > Spread too high for ", pair.symbol);
            return;
        }
        
        if(!IsTradeAllowed(pair.symbol, true))
        {
            Print(__FUNCTION__, " > Trade limit reached for ", pair.symbol);
            return;
        }
        
        DeletePendingOrders(pair.symbol, ORDER_TYPE_BUY_STOP);
        
        double currentBid = SymbolInfoDouble(pair.symbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(pair.symbol, SYMBOL_ASK);
        
        double buyOrderPrice = lastZigZagHigh + Buffer * _Point;
        buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
        
        if(buyOrderPrice <= currentAsk)
        {
            buyOrderPrice = currentAsk + _Point;
            buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
        }
        
        // Calculate stop loss if enabled
        double sl = 0;
        if(FixedSL > 0)
        {
            sl = buyOrderPrice - FixedSL * _Point;
            sl = NormalizeDouble(sl, _Digits);
        }
        
        // Calculate take profit if enabled
        double tp = 0;
        if(FixedTP > 0)
        {
            tp = buyOrderPrice + FixedTP * _Point;
            tp = NormalizeDouble(tp, _Digits);
        }
        
        double lotSize = CalculatePositionSize(pair.symbol, sl, buyOrderPrice, true);
        datetime expiration = 0;
        
        if(trade.BuyStop(lotSize, buyOrderPrice, pair.symbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            Print(__FUNCTION__, " > Buy Stop order placed for ", pair.symbol, " at ", buyOrderPrice);
            pair.posTicket = trade.ResultOrder();
            isFirstSignalAfterBullish = false;  // Reset le flag après placement de l'ordre
            lastLowBeforeBullish = 0.0;  // Reset pour le prochain signal
        }
        else
        {
            Print(__FUNCTION__, " > Failed to place Buy Stop order. Error: ", GetLastError());
            isFirstSignalAfterBullish = false;  // Reset aussi en cas d'échec pour éviter de réessayer
            lastLowBeforeBullish = 0.0;
        }
    }
    
    // Check for first Low in bullish Supertrend
    if(isFirstSignalAfterBullish && close1 > st[1])  // En tendance haussière Supertrend
    {
        Print(__FUNCTION__, " > Checking for first Low in Bullish Supertrend for ", pair.symbol);
        Print(__FUNCTION__, " > zigzagHighLow[0]: ", zigzagHighLow[0], ", zigzag[0]: ", zigzag[0], ", lastZigZagHigh: ", lastZigZagHigh, ", lastZigZagLow: ", lastZigZagLow);
        
        // Vérifier si nous avons un nouveau Low en comparant avec la dernière valeur stockée
        if(zigzagHighLow[0] == 0.0 && lastZigZagLow != 0.0)  // Si c'est un point bas et que nous avons déjà une valeur de référence
        {
            Print("Checking for ZigZag Low change - Current Low: ", lastZigZagLow, ", Previous Low: ", previousZigZagLow);
            // Ne vérifier que si c'est le premier Low après le changement de tendance et que la valeur précédente n'est pas 0
            if(lastLowBeforeBullish == 0.0 && zigzag[0] != 0.0 && previousZigZagLow != 0.0 && zigzag[0] != previousZigZagLow)  // Premier Low après le changement de tendance et la valeur a changé
            {
                lastLowBeforeBullish = lastZigZagLow;  // Utiliser lastZigZagLow au lieu de zigzag[0]
                Print(__FUNCTION__, " > First Low in Bullish Supertrend detected for ", pair.symbol, " at ", lastZigZagLow);
                
                if(!IsSpreadAcceptable(pair.symbol))
                {
                    Print(__FUNCTION__, " > Spread too high for ", pair.symbol);
                    return;
                }
                
                if(!IsTradeAllowed(pair.symbol, true))
                {
                    Print(__FUNCTION__, " > Trade limit reached for ", pair.symbol);
                    return;
                }
                
                DeletePendingOrders(pair.symbol, ORDER_TYPE_BUY_STOP);
                
                double currentBid = SymbolInfoDouble(pair.symbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(pair.symbol, SYMBOL_ASK);
                
                double buyOrderPrice = lastZigZagHigh + Buffer * _Point;
                buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
                
                if(buyOrderPrice <= currentAsk)
                {
                    buyOrderPrice = currentAsk + _Point;
                    buyOrderPrice = NormalizeDouble(buyOrderPrice, _Digits);
                }
                
                // Calculate stop loss if enabled
                double sl = 0;
                if(FixedSL > 0)
                {
                    sl = buyOrderPrice - FixedSL * _Point;
                    sl = NormalizeDouble(sl, _Digits);
                }
                
                // Calculate take profit if enabled
                double tp = 0;
                if(FixedTP > 0)
                {
                    tp = buyOrderPrice + FixedTP * _Point;
                    tp = NormalizeDouble(tp, _Digits);
                }
                
                double lotSize = CalculatePositionSize(pair.symbol, sl, buyOrderPrice, true);
                datetime expiration = 0;
                
                if(trade.BuyStop(lotSize, buyOrderPrice, pair.symbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    Print(__FUNCTION__, " > Buy Stop order placed for ", pair.symbol, " at ", buyOrderPrice);
                    pair.posTicket = trade.ResultOrder();
                    isFirstSignalAfterBullish = false;  // Reset le flag après placement de l'ordre
                    lastLowBeforeBullish = 0.0;  // Reset pour le prochain signal
                }
                else
                {
                    Print(__FUNCTION__, " > Failed to place Buy Stop order. Error: ", GetLastError());
                    isFirstSignalAfterBullish = false;  // Reset aussi en cas d'échec pour éviter de réessayer
                    lastLowBeforeBullish = 0.0;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Sell Signal                                                 |
//+------------------------------------------------------------------+
void HandleSellSignal(TradingPair &pair, double &st[], double close1, double close2, double &zigzagHighLow[], double &zigzag[])
{
    // Vérifier si une position de vente existe déjà si l'option est activée
    if(CheckExistingPositions && HasPosition(pair.symbol, POSITION_TYPE_SELL))
    {
        Print(__FUNCTION__, " > Sell position already exists for ", pair.symbol);
        return;
    }

    // Check for Supertrend direction change to bullish
    if(close1 > st[1] && close2 < st[0])
    {
        isFirstSignalAfterBullish = true;
        isFirstSignalAfterBearish = false;
        
        Print(__FUNCTION__, " > Supertrend turned bullish for ", pair.symbol);
        
        if(!IsSpreadAcceptable(pair.symbol))
        {
            Print(__FUNCTION__, " > Spread too high for ", pair.symbol);
            return;
        }
        
        if(!IsTradeAllowed(pair.symbol, false))
        {
            Print(__FUNCTION__, " > Trade limit reached for ", pair.symbol);
            return;
        }
        
        DeletePendingOrders(pair.symbol, ORDER_TYPE_SELL_STOP);
        
        double currentBid = SymbolInfoDouble(pair.symbol, SYMBOL_BID);
        double currentAsk = SymbolInfoDouble(pair.symbol, SYMBOL_ASK);
        
        // Calculer le prix de l'ordre en utilisant le dernier Low ZigZag et le buffer
        double sellOrderPrice = lastZigZagLow - Buffer * _Point;
        sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
        
        if(sellOrderPrice >= currentBid)
        {
            sellOrderPrice = currentBid - _Point;
            sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
        }
        
        // Calculate stop loss if enabled
        double sl = 0;
        if(FixedSL > 0)
        {
            sl = sellOrderPrice + FixedSL * _Point;
            sl = NormalizeDouble(sl, _Digits);
        }
        
        // Calculate take profit if enabled
        double tp = 0;
        if(FixedTP > 0)
        {
            tp = sellOrderPrice - FixedTP * _Point;
            tp = NormalizeDouble(tp, _Digits);
        }
        
        double lotSize = CalculatePositionSize(pair.symbol, sl, sellOrderPrice, false);
        datetime expiration = 0;
        
        if(trade.SellStop(lotSize, sellOrderPrice, pair.symbol, sl, tp, ORDER_TIME_GTC, expiration))
        {
            Print(__FUNCTION__, " > Sell Stop order placed for ", pair.symbol, " at ", sellOrderPrice);
            pair.posTicket = trade.ResultOrder();
            isFirstSignalAfterBearish = false;  // Reset le flag après placement de l'ordre
            lastHighBeforeBearish = 0.0;  // Reset pour le prochain signal
        }
        else
        {
            Print(__FUNCTION__, " > Failed to place Sell Stop order. Error: ", GetLastError());
            isFirstSignalAfterBearish = false;  // Reset aussi en cas d'échec pour éviter de réessayer
            lastHighBeforeBearish = 0.0;
        }
    }
    
    // Check for first High in bearish Supertrend
    if(isFirstSignalAfterBearish && close1 < st[1])  // En tendance baissière Supertrend
    {
        Print(__FUNCTION__, " > Checking for first High in Bearish Supertrend for ", pair.symbol);
        Print(__FUNCTION__, " > zigzagHighLow[0]: ", zigzagHighLow[0], ", zigzag[0]: ", zigzag[0], ", lastZigZagLow: ", lastZigZagLow, ", lastZigZagHigh: ", lastZigZagHigh);
        
        // Vérifier si nous avons un nouveau High en comparant avec la dernière valeur stockée
        if(zigzagHighLow[0] != 0.0 && lastZigZagHigh != 0.0)  // Si c'est un point haut et que nous avons déjà une valeur de référence
        {
            Print("Checking for ZigZag High change - Current High: ", lastZigZagHigh, ", Previous High: ", previousZigZagHigh);
            // Ne vérifier que si c'est le premier High après le changement de tendance et que la valeur précédente n'est pas 0
            if(lastHighBeforeBearish == 0.0 && zigzag[0] != 0.0 && previousZigZagHigh != 0.0 && zigzag[0] != previousZigZagHigh)  // Premier High après le changement de tendance et la valeur a changé
            {
                lastHighBeforeBearish = lastZigZagHigh;  // Utiliser lastZigZagHigh au lieu de zigzag[0]
                Print(__FUNCTION__, " > First High in Bearish Supertrend detected for ", pair.symbol, " at ", lastZigZagHigh);
                
                if(!IsSpreadAcceptable(pair.symbol))
                {
                    Print(__FUNCTION__, " > Spread too high for ", pair.symbol);
                    return;
                }
                
                if(!IsTradeAllowed(pair.symbol, false))
                {
                    Print(__FUNCTION__, " > Trade limit reached for ", pair.symbol);
                    return;
                }
                
                DeletePendingOrders(pair.symbol, ORDER_TYPE_SELL_STOP);
                
                double currentBid = SymbolInfoDouble(pair.symbol, SYMBOL_BID);
                double currentAsk = SymbolInfoDouble(pair.symbol, SYMBOL_ASK);
                
                double sellOrderPrice = lastZigZagLow - Buffer * _Point;
                sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
                
                if(sellOrderPrice >= currentBid)
                {
                    sellOrderPrice = currentBid - _Point;
                    sellOrderPrice = NormalizeDouble(sellOrderPrice, _Digits);
                }
                
                // Calculate stop loss if enabled
                double sl = 0;
                if(FixedSL > 0)
                {
                    sl = sellOrderPrice + FixedSL * _Point;
                    sl = NormalizeDouble(sl, _Digits);
                }
                
                // Calculate take profit if enabled
                double tp = 0;
                if(FixedTP > 0)
                {
                    tp = sellOrderPrice - FixedTP * _Point;
                    tp = NormalizeDouble(tp, _Digits);
                }
                
                double lotSize = CalculatePositionSize(pair.symbol, sl, sellOrderPrice, false);
                datetime expiration = 0;
                
                if(trade.SellStop(lotSize, sellOrderPrice, pair.symbol, sl, tp, ORDER_TIME_GTC, expiration))
                {
                    Print(__FUNCTION__, " > Sell Stop order placed for ", pair.symbol, " at ", sellOrderPrice);
                    pair.posTicket = trade.ResultOrder();
                    isFirstSignalAfterBearish = false;  // Reset le flag après placement de l'ordre
                    lastHighBeforeBearish = 0.0;  // Reset pour le prochain signal
                }
                else
                {
                    Print(__FUNCTION__, " > Failed to place Sell Stop order. Error: ", GetLastError());
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
    datetime currentTime = TimeCurrent();
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    int currentHour = time.hour;
    int currentMinute = time.min;
    
    // Convert to GMT if needed
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
    
    // Convert current time to minutes for easier comparison
    int currentTimeInMinutes = currentHour * 60 + currentMinute;
    int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
    int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
    
    // Handle case where trading period crosses midnight
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
    // Check if we have a low point followed by a high point
    if(zigzagHighLow[1] == 0.0 && zigzagHighLow[0] != 0.0)
    {
        // Check if the high point is higher than the previous low point
        if(zigzag[0] > zigzag[1])
        {
            return true;
        }
    }
    return false;
}

bool IsZigZagSellSignal(double &zigzag[], double &zigzagHighLow[])
{
    // Check if we have a high point followed by a low point
    if(zigzagHighLow[1] != 0.0 && zigzagHighLow[0] == 0.0)
    {
        // Check if the low point is lower than the previous high point
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
void HandleRSIPartialClose(TradingPair &pair)
{
    if(!EnableRSIPartialClose || PartialClosePercent <= 0 || MinProfitForPartialClose <= 0)
        return;
        
    if(pair.posTicket <= 0)
        return;
        
    if(!PositionSelectByTicket(pair.posTicket))
        return;
        
    // Get current RSI value
    double rsi[];
    ArraySetAsSeries(rsi, true);
    if(CopyBuffer(pair.rsiHandle, 0, 0, 2, rsi) <= 0)
        return;
        
    double currentRSI = rsi[0];
    double previousRSI = pair.lastRSI;
    pair.lastRSI = currentRSI;
    
    // Get position details
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double positionVolume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Calculate current profit in points
    double profitPoints = 0;
    if(posType == POSITION_TYPE_BUY)
        profitPoints = (currentPrice - openPrice) / _Point;
    else if(posType == POSITION_TYPE_SELL)
        profitPoints = (openPrice - currentPrice) / _Point;
        
    // Check if profit is sufficient
    if(profitPoints < MinProfitForPartialClose)
        return;
        
    // Check RSI conditions and handle partial close
    if(posType == POSITION_TYPE_BUY)
    {
        // Check for RSI crossing above upper level
        if(previousRSI < RSI_UpperLevel && currentRSI > RSI_UpperLevel && !pair.rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(trade.PositionClosePartial(pair.posTicket, closeVolume))
            {
                Print(__FUNCTION__, " > Partial close of ", closeVolume, " lots for BUY position #", pair.posTicket);
                pair.rsiPartialCloseDone = true;
            }
        }
        // Reset flag when RSI goes below upper level
        else if(currentRSI < RSI_UpperLevel)
        {
            pair.rsiPartialCloseDone = false;
        }
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        // Check for RSI crossing below lower level
        if(previousRSI > RSI_LowerLevel && currentRSI < RSI_LowerLevel && !pair.rsiPartialCloseDone)
        {
            double closeVolume = NormalizeDouble(positionVolume * PartialClosePercent / 100.0, 2);
            if(trade.PositionClosePartial(pair.posTicket, closeVolume))
            {
                Print(__FUNCTION__, " > Partial close of ", closeVolume, " lots for SELL position #", pair.posTicket);
                pair.rsiPartialCloseDone = true;
            }
        }
        // Reset flag when RSI goes above lower level
        else if(currentRSI > RSI_LowerLevel)
        {
            pair.rsiPartialCloseDone = false;
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
        
    for(int i = 0; i < ArraySize(pairs); i++)
    {
        int bars = iBars(pairs[i].symbol, Timeframe);
        if(pairs[i].totalBars != bars)
        {
            pairs[i].totalBars = bars;
            
            // S'assurer que les tableaux sont dimensionnés correctement
            ArrayResize(st, 3);
            ArrayResize(zigzag, 3);
            ArrayResize(zigzagHighLow, 3);
            
            // Copier les valeurs des indicateurs
            int copied = CopyBuffer(pairs[i].stHandle, 0, 0, 3, st);
            if(copied <= 0)
            {
                Print("Erreur CopyBuffer Supertrend: ", GetLastError());
                continue;
            }
            
            // Vérifier si le handle ZigZag est toujours valide
            if(pairs[i].zzHandle == INVALID_HANDLE)
            {
                Print("Error initializing ZigZag indicator for ", pairs[i].symbol);
                continue;
            }

            // Attendre un peu pour s'assurer que l'indicateur est prêt
            Sleep(100);

            // Copier les valeurs ZigZag
            copied = CopyBuffer(pairs[i].zzHandle, 0, 0, 3, zigzag);
            if(copied <= 0)
            {
                Print("Error copying ZigZag main buffer: ", GetLastError(), " for ", pairs[i].symbol);
                continue;
            }
            
            // Copier les valeurs HighLow
            copied = CopyBuffer(pairs[i].zzHandle, 1, 0, 3, zigzagHighLow);
            if(copied <= 0)
            {
                Print("Error copying ZigZag HighLow buffer: ", GetLastError(), " for ", pairs[i].symbol);
                continue;
            }

            double close1 = iClose(pairs[i].symbol, Timeframe, 1);
            double close2 = iClose(pairs[i].symbol, Timeframe, 2);
            
            if(close1 == 0 || close2 == 0)
            {
                Print("Attention: Prix de clôture invalides pour ", pairs[i].symbol);
                continue;
            }
            
            HandleTrailingStopLoss(pairs[i], st);
            
            // Mettre à jour les derniers high et low du ZigZag
            // Ne vérifier que la valeur la plus récente
            if(zigzagHighLow[0] != 0.0) // High point
            {
                if(lastZigZagHigh != zigzag[0] && zigzag[0] != 0.0) // Ne mettre à jour que si la valeur change et n'est pas 0
                {
                    previousZigZagHigh = lastZigZagHigh;  // Sauvegarder l'ancienne valeur
                    Print("ZigZag High changed from ", lastZigZagHigh, " to ", zigzag[0], " (Change: ", zigzag[0] - lastZigZagHigh, " points)");
                    lastZigZagHigh = zigzag[0];
                }
            }
            else // Low point
            {
                if(lastZigZagLow != zigzag[0] && zigzag[0] != 0.0) // Ne mettre à jour que si la valeur change et n'est pas 0
                {
                    previousZigZagLow = lastZigZagLow;  // Sauvegarder l'ancienne valeur
                    Print("ZigZag Low changed from ", lastZigZagLow, " to ", zigzag[0], " (Change: ", zigzag[0] - lastZigZagLow, " points)");
                    lastZigZagLow = zigzag[0];
                }
            }
            
            // Vérifier les signaux ZigZag
            if(IsZigZagBuySignal(zigzag, zigzagHighLow))
            {
                // Vous pouvez ajouter ici votre logique de trading pour les signaux d'achat ZigZag
            }
            
            if(IsZigZagSellSignal(zigzag, zigzagHighLow))
            {
                // Vous pouvez ajouter ici votre logique de trading pour les signaux de vente ZigZag
            }
            
            // First check for Supertrend direction changes and close positions
            if(CloseOnOppositeSupertrend)
            {
                // Check for BUY positions when Supertrend turns bearish
                if(close1 < st[1] && close2 > st[0])  // Supertrend devient baissière
                {
                    for(int j = PositionsTotal() - 1; j >= 0; j--)
                    {
                        if(PositionSelectByTicket(PositionGetTicket(j)))
                        {
                            if(PositionGetString(POSITION_SYMBOL) == pairs[i].symbol && 
                               PositionGetInteger(POSITION_MAGIC) == Magic &&
                               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                            {
                                trade.PositionClose(PositionGetTicket(j));
                                Print(__FUNCTION__, " > Closed BUY position due to Supertrend direction change for ", pairs[i].symbol);
                            }
                        }
                    }
                }
                
                // Check for SELL positions when Supertrend turns bullish
                if(close1 > st[1] && close2 < st[0])  // Supertrend devient haussière
                {
                    for(int j = PositionsTotal() - 1; j >= 0; j--)
                    {
                        if(PositionSelectByTicket(PositionGetTicket(j)))
                        {
                            if(PositionGetString(POSITION_SYMBOL) == pairs[i].symbol && 
                               PositionGetInteger(POSITION_MAGIC) == Magic &&
                               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                            {
                                trade.PositionClose(PositionGetTicket(j));
                                Print(__FUNCTION__, " > Closed SELL position due to Supertrend direction change for ", pairs[i].symbol);
                            }
                        }
                    }
                }
            }
            
            // Then handle trading signals
            HandleBuySignal(pairs[i], st, close1, close2, zigzagHighLow, zigzag);
            HandleSellSignal(pairs[i], st, close1, close2, zigzagHighLow, zigzag);
            
            // Handle RSI partial close if enabled
            if(EnableRSIPartialClose)
            {
                HandleRSIPartialClose(pairs[i]);
            }
            
            // Vérifier que les tableaux ont des valeurs avant d'afficher le Comment
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
                        "Position Ticket: ", pairs[i].posTicket, "\n",
                        "\n=== ZigZag Parameters ===\n",
                        "Depth: ", pairs[i].zzDepth, "\n",
                        "Deviation: ", pairs[i].zzDeviation, "\n",
                        "Backstep: ", pairs[i].zzBackstep, "\n",
                        "\n=== Price Info ===\n",
                        "Close[1]: ", close1, "\n",
                        "Close[2]: ", close2);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade function                                                    |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Check if any positions were closed
    for(int i = 0; i < ArraySize(pairs); i++)
    {
        if(pairs[i].posTicket > 0)
        {
            if(!PositionSelectByTicket(pairs[i].posTicket))
            {
                // Position was closed, clear the ticket
                pairs[i].posTicket = 0;
            }
        }
    }

    // Check for triggered pending orders
    for(int i = 0; i < ArraySize(pairs); i++)
    {
        // Check all positions for this symbol
        for(int j = 0; j < PositionsTotal(); j++)
        {
            if(PositionGetSymbol(j) == pairs[i].symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                ulong ticket = PositionGetTicket(j);
                // If this is a new position (not already tracked)
                if(ticket != pairs[i].posTicket)
                {
                    pairs[i].posTicket = ticket;
                    Print(__FUNCTION__, " > Updated posTicket for ", pairs[i].symbol, " to ", ticket);
                }
            }
        }
    }
} 
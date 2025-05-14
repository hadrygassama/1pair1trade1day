//+------------------------------------------------------------------+
//|                                                    SupertrendEA.mq5 |
//|                                                                     |
//|                                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

// Input parameters

input double LotSize = 0.1;          // Lot
input int TpFactor = 2.0;            // Take Profit Factor
input bool TslActive = true;         // Trailing Stop Loss Active

input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input int    ATR_Period = 10;        // ATR Period
input double ATR_Multiplier = 3.0;   // ATR Multiplier

input bool IsMaFilter = true;
input ENUM_TIMEFRAMES MaTimeframe = PERIOD_CURRENT;
input int MaPeriod = 200;
input ENUM_MA_METHOD MaMethod = MODE_SMA;
input ENUM_APPLIED_PRICE MaPrice = PRICE_CLOSE;


// Global variables
int stHandle;
int maHandle;
int totalBars;

CTrade trade;
ulong posTicket;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize Supertrend 
    totalBars = iBars(_Symbol, Timeframe);
    stHandle = iCustom(_Symbol, Timeframe, "Supertrend.ex5", ATR_Period, ATR_Multiplier);
    maHandle = iMA(_Symbol, MaTimeframe, MaPeriod, 0, MaMethod, MaPrice);
    
    if(stHandle == INVALID_HANDLE)
    {
        Print("Erreur lors de l'appel à Supertrend.ex5");
        return(INIT_FAILED);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(stHandle != INVALID_HANDLE)
        IndicatorRelease(stHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{

    int bars = iBars(_Symbol, Timeframe);
    if(totalBars != bars)
    {
        totalBars = bars;

        double st[];
        CopyBuffer(stHandle, 0, 0, 3, st) ;

        double ma[];
        CopyBuffer(maHandle, 0, 1, 1, ma);

        double close1 = iClose(_Symbol, Timeframe, 1);
        double close2 = iClose(_Symbol, Timeframe, 2);

        if(TslActive)
        {
            if(posTicket>0)
            {
                if(PositionSelectByTicket(posTicket))
                {
                    double sl = st[1];
                    sl = NormalizeDouble(sl, _Digits);

                    double posSl = PositionGetDouble(POSITION_SL);
                    double posTp = PositionGetDouble(POSITION_TP);

                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                    {
                        if(sl > posSl)
                        {
                            if(trade.PositionModify(posTicket, sl, posTp))
                            {
                                Print(__FUNCTION__, " > Pos #",posTicket," was modified ...");
                            }
                        }
                    } 
                    else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) 
                    {
                        if(sl < posSl || posSl == 0)
                        {
                            if(trade.PositionModify(posTicket, sl, posTp))
                            {
                                Print(__FUNCTION__, " > Pos #",posTicket," was modified ...");
                            }
                        }
                    }
                }
            }
        }

        if( close1 > st[1] && close2 < st[0])
        {
           Print(__FUNCTION__, " > Buy Signal ...");

           if(posTicket>0)
           {
                if(PositionSelectByTicket(posTicket))
                {
                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    {
                        if(trade.PositionClose(posTicket))
                        {
                            Print(__FUNCTION__, " > Pos #",posTicket," was closed ...");
                        }
                    }
                }
           }

           if(IsMaFilter || close1 > ma[0])
           {
                double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
                ask = NormalizeDouble(ask, _Digits);

                double sl = st[1];
                sl = NormalizeDouble(sl, _Digits);
                
                double tp=0;
                if (TpFactor > 0) tp = ask + (ask - sl) * TpFactor;
                tp = NormalizeDouble(tp, _Digits);

                if(trade.Buy(LotSize,_Symbol,ask,sl,tp))
                {
                        if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
                        {
                            posTicket = trade.ResultOrder();
                        }
                }
           }
        }

        else if( close1 < st[1] && close2 > st[0])
        {
            Print(__FUNCTION__, " > Sell Signal ...");

            if(posTicket>0)
           {
                if(PositionSelectByTicket(posTicket))
                {
                    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    {
                        if(trade.PositionClose(posTicket))
                        {
                            Print(__FUNCTION__, " > Pos #",posTicket," was closed ...");
                        }
                    }
                }
           }

           if(IsMaFilter || close1 < ma[0])
           {
                double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
                bid = NormalizeDouble(bid, _Digits);

                double sl = st[1];
                sl = NormalizeDouble(sl, _Digits);

                double tp=0;
                if (TpFactor > 0)  tp = bid - (sl - bid) * TpFactor;
                tp = NormalizeDouble(tp, _Digits);          

                if(trade.Sell(LotSize,_Symbol,bid,sl,tp))
                {
                        if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
                        {
                            posTicket = trade.ResultOrder();
                        }
                }
           }
        }
        
        Comment("ST Value [0]: ", st[0], 
                "\nST Value [1]: ", st[1], 
                "\nST Value [2]: ", st[2],
                "\nMA Value [0]: ", ma[0],
                "\nPos Ticket:  ",posTicket);
        
    }
}

//+------------------------------------------------------------------+
//| Trade function                                                    |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Handle trade events if needed
} 
//+------------------------------------------------------------------+
//|                                                      ZigZag.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

// Plot properties
#property indicator_label1  "ZigZag"
#property indicator_type1   DRAW_SECTION
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "HighLow"
#property indicator_type2   DRAW_NONE

// Input parameters
input int    Depth = 12;        // Depth
input int    Deviation = 5;     // Deviation
input int    Backstep = 3;      // Backstep

// Indicator buffers
double ZigZagBuffer[];
double HighLowBuffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set indicator buffers
    SetIndexBuffer(0, ZigZagBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, HighLowBuffer, INDICATOR_CALCULATIONS);
    
    // Set indicator digits
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
    
    // Set indicator name
    IndicatorSetString(INDICATOR_SHORTNAME, "ZigZag(" + IntegerToString(Depth) + "," + IntegerToString(Deviation) + "," + IntegerToString(Backstep) + ")");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(rates_total < Depth) return(0);
    
    int limit = rates_total - prev_calculated;
    if(prev_calculated > 0) limit++;
    
    // Initialize arrays
    double highBuffer[];
    double lowBuffer[];
    ArrayResize(highBuffer, rates_total);
    ArrayResize(lowBuffer, rates_total);
    
    // Find highs and lows
    for(int i = Depth; i < rates_total; i++)
    {
        double highestHigh = high[i];
        double lowestLow = low[i];
        
        for(int j = 0; j < Depth; j++)
        {
            if(high[i-j] > highestHigh) highestHigh = high[i-j];
            if(low[i-j] < lowestLow) lowestLow = low[i-j];
        }
        
        highBuffer[i] = highestHigh;
        lowBuffer[i] = lowestLow;
    }
    
    // Calculate ZigZag
    int lastHigh = 0;
    int lastLow = 0;
    double lastHighPrice = 0;
    double lastLowPrice = 0;
    
    for(int i = Depth; i < rates_total; i++)
    {
        if(high[i] == highBuffer[i] && high[i] > lastHighPrice)
        {
            lastHigh = i;
            lastHighPrice = high[i];
            ZigZagBuffer[i] = high[i];
            HighLowBuffer[i] = 1;
        }
        else if(low[i] == lowBuffer[i] && low[i] < lastLowPrice)
        {
            lastLow = i;
            lastLowPrice = low[i];
            ZigZagBuffer[i] = low[i];
            HighLowBuffer[i] = -1;
        }
    }
    
    return(rates_total);
} 
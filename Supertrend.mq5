#property version   "1.00"

#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots 1

#property indicator_label1  "SuperTrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrGreen, clrRed

input int    Periods=10;
input double Multiplier=3;

double SuperTrend[];
double ColorBuffer[];
double Atr[];
double Up[];
double Down[];
double Middle[];
double trend[];

int atrHandle;
int changeOfTrend;
int flag;
int flagh;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- indicator buffers mapping
   SetIndexBuffer(0,SuperTrend,INDICATOR_DATA);
   SetIndexBuffer(1,ColorBuffer,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,Atr,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,Up,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,Down,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,Middle,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,trend,INDICATOR_CALCULATIONS);

   // Initialize arrays
   ArraySetAsSeries(SuperTrend, true);
   ArraySetAsSeries(ColorBuffer, true);
   ArraySetAsSeries(Atr, true);
   ArraySetAsSeries(Up, true);
   ArraySetAsSeries(Down, true);
   ArraySetAsSeries(Middle, true);
   ArraySetAsSeries(trend, true);

   atrHandle=iATR(_Symbol,_Period,Periods);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Error creating ATR indicator");
      return(INIT_FAILED);
   }

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
   if(rates_total < Periods) return(0);

   int to_copy;
   if(prev_calculated > rates_total || prev_calculated < 0) 
      to_copy = rates_total;
   else
   {
      to_copy = rates_total - prev_calculated;
      if(prev_calculated > 0) to_copy++;
   }

   if(IsStopped()) return(0);

   if(CopyBuffer(atrHandle,0,0,to_copy,Atr) <= 0)
   {
      Print("Error copying ATR buffer");
      return(0);
   }

   int first;
   if(prev_calculated > rates_total || prev_calculated <= 0)
   {
      first = Periods;
      // Initialize first values
      for(int i = 0; i < first; i++)
      {
         trend[i] = 1;  // Initialize with bullish trend
         Middle[i] = (high[i] + low[i]) / 2;
         Up[i] = Middle[i] + (Multiplier * Atr[i]);
         Down[i] = Middle[i] - (Multiplier * Atr[i]);
         SuperTrend[i] = Down[i];
         ColorBuffer[i] = 0.0;
      }
   }
   else
   {
      first = prev_calculated - 1;
   }

   for(int i = first; i < rates_total && !IsStopped(); i++)
   {
      Middle[i] = (high[i] + low[i]) / 2;
      Up[i] = Middle[i] + (Multiplier * Atr[i]);
      Down[i] = Middle[i] - (Multiplier * Atr[i]);

      if(close[i] > Up[i-1]) 
      {
         trend[i] = 1;
         if(trend[i-1] == -1) changeOfTrend = 1;
      }
      else if(close[i] < Down[i-1]) 
      {
         trend[i] = -1;
         if(trend[i-1] == 1) changeOfTrend = 1;
      }
      else 
      {
         trend[i] = trend[i-1];
         changeOfTrend = 0;
      }

      if(trend[i] < 0 && trend[i-1] > 0) 
         flag = 1;
      else 
         flag = 0;

      if(trend[i] > 0 && trend[i-1] < 0) 
         flagh = 1;
      else 
         flagh = 0;

      if(trend[i] > 0 && Down[i] < Down[i-1])
         Down[i] = Down[i-1];

      if(trend[i] < 0 && Up[i] > Up[i-1])
         Up[i] = Up[i-1];

      if(flag == 1)
         Up[i] = Middle[i] + (Multiplier * Atr[i]);

      if(flagh == 1)
         Down[i] = Middle[i] - (Multiplier * Atr[i]);

      if(trend[i] == 1) 
      {
         SuperTrend[i] = Down[i];
         if(changeOfTrend == 1) 
         {
            SuperTrend[i-1] = SuperTrend[i-2];
            changeOfTrend = 0;
         }
         ColorBuffer[i] = 0.0;
      }
      else if(trend[i] == -1) 
      {
         SuperTrend[i] = Up[i];
         if(changeOfTrend == 1) 
         {
            SuperTrend[i-1] = SuperTrend[i-2];
            changeOfTrend = 0;
         }
         ColorBuffer[i] = 1.0;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
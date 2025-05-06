//+------------------------------------------------------------------+
//|                                                      StdLibErr.mqh |
//|                        Basic error handling and logging functions |
//+------------------------------------------------------------------+

// Function to log errors
void LogError(string message) {
    Print("Error: ", message);
}

// Function to handle errors
void HandleError(int errorCode) {
    string errorMessage = ErrorDescription(errorCode);
    LogError(errorMessage);
}

// Function to get error description
string ErrorDescription(int errorCode) {
    switch(errorCode) {
        case ERR_NO_ERROR: return "No error";
        case ERR_COMMON_ERROR: return "Common error";
        // Add more error codes and descriptions as needed
        default: return "Unknown error";
    }
} 
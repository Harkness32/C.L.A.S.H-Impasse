// semlock
//
// Initialization: setup a public boolean variable and set it to false (or true if you want it initially taken)
//         BoolVarName = false;
//
// Usage:  SEM_LOCK(BoolVarName);       - checks every 0.001sec, should finish < 1sec
//         SEM_LOCK_LONG(BoolVarName);  - checks every 0.1sec,   should finish < 10sec
//         SEM_UNLOCK(BoolVarName);

#undef SEM_DEBUG // use #define or #undef

#ifdef SEM_DEBUG
#define SEM_LOCK(SEM)   if (true) then { \
    SEM_LIST pushBackUnique 'SEM'; \
    private _lockOk= false; \
    waitUntil { \
        isNil { \
            if !(SEM) then { \
                SEM = true; \
                _lockOk=true; \
            }; \
        }; \
        if (!_lockOk) then { \
            sleep 0.001; \
        }; \
        _lockOk \
    }; \
    if (SEM_SHOW_ALL) then { \
        diag_log format ["SKL_Sem Locked %1: %2 # %3",'SEM',__FILE_NAME__,__LINE__]; \
    }; \
    call compile format["%1_TIME=time;%1_TO=time+1",'SEM']; \
}

#define SEM_LOCK_LONG(SEM) if(true)then{ \
    private _lockOk=false;waitUntil{isNil {if !(SEM)then{SEM=true;_lockOk=true}};if(!_lockOk)then{sleep 0.1;};_lockOk}; \
    call compile format["%1_TIME=time;%1_TO=time+10",'SEM']; \
}

#define SEM_UNLOCK(SEM) if( SEM_SHOW_ALL || {call compile format["time > %1_TO",'SEM']}) then { \
    diag_log format ["%5SKL_Sem Unlocked %1 sec: %2 :, %3# %4", \
        (round ((call compile format["time-%1_Time",'SEM'])*1000))/1000, \
        'SEM', \
        __FILE_NAME__, \
        __LINE__, \
        if(call compile format["time > %1_TO",'SEM']) then {"Error Pos: Long SemLock: "} else {""} \
    ] \
}; \
SEM=false;

#define SEM_CHECK_CODE \
if( isNil "SEM_CHECK") then { \
    SEM_SHOW_ALL = false; \
    SEM_LIST = []; \
    SEM_CHECK = { \
        private _result = []; \
        { \
            _x params ["_semName"]; \
            private _sem = call compile _semName; \
            diag_log [_sem,_semName]; \
            if(_sem) then {_result pushBack _semName}; \
        } forEach SEM_LIST; \
        _result \
    }; \
}
SEM_CHECK_CODE; // do this in 1 line to keep __LINE__ usage more accurate
#else
#define SEM_LOCK(SEM)      if(true)then{private _lockOk=false;waitUntil{isNil {if !(SEM)then{SEM=true;_lockOk=true}};if(!_lockOk)then{sleep 0.001;};_lockOk}}
#define SEM_LOCK_LONG(SEM) if(true)then{private _lockOk=false;waitUntil{isNil {if !(SEM)then{SEM=true;_lockOk=true}};if(!_lockOk)then{sleep 0.1;};_lockOk}}
#define SEM_UNLOCK(SEM)    SEM=false;
#endif
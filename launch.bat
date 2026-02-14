odin build . -debug -out:hexabomb.exe 
:: -subsystem:windows

taskkill /IM hexabomb.exe /F

start hexabomb.exe --local --clearlogs --port=6969 --clientname=player_1
start hexabomb.exe --local --clearlogs --port=6970 --clientname=player_2

#!/bin/bash

PIDFILE=SERVER_PIDS.txt
LOGFILE=.LIST_OF_CLIENT_FIFOS.txt

function Shutdown()
{
   #stop managing new connection requests
   kill -STOP $LISTENER_PID $INC_CONN_HANDLER_PID

   #Say goodbye to every client
   for fifo in $(get_all_client_fifos)
   do
      echo "_SERVER_|BYE" > $fifo;
   done

   #kill every process of the server.
   cat $PIDFILE | gawk -F'|' '{print $2}' | xargs kill

   #remove files, but keep the pids log
   rm connection_pipe \
      ack_pipe        \
      $LOGFILE        \
      pids_pipe       \
      s_data_pipe     \
      .conv.log       \
      .conn.* &> /dev/null

   exit 0
}


function registra_pid()
{
   echo "$1|$2|$(date '+%Y%m%d%H%M%S%N')" > pids_pipe;
}

function registra_log()
{
   echo "$(date '+%Y%m%d%H%M%S%N')|$@" >> $LOGFILE;
}


function get_all_client_fifos()
{
   cat $LOGFILE | gawk -F'|' '{print $3}'
}

function get_all_logged_users()
{
   cat $LOGFILE | gawk -F'|' '{print $2}'
}


function broadcast()
{
   for fifo in $(get_all_client_fifos)
   do
      echo "$@" > $fifo;
   done
}

#$1 -> cliente al que mandar la lista
function mandar_listado()
{
   echo "_SERVER_|_WHO_|$(get_all_logged_users | tr '\n' '|')" > \
        $(get_client $1 | cut -d"|" -f2)
}

#$1 -> nombre cliente
#$2 -> nombre fifo
function add_client()
{
   broadcast "$1|_HI_"
   echo "$(date '+%Y%m%d%H%M%S%N')|$1|$2" >> $LOGFILE;
}

#$1 -> nombre_cliente
function get_client()
{
   cat $LOGFILE | gawk -F'|' '{print $2"|"$3}' | grep "\<$1\>"
}

function end_client()
{
   if [ $# -eq 1 ]
   then
      cliente=$(get_client $1 | cut -d"|" -f1)
      fifo=$(   get_client $1 | cut -d"|" -f2)
      if [ "$cliente" != "" ] #cliente existente
      then
         cat $LOGFILE | grep -v "\<$1\>" > $LOGFILE.aux
         mv $LOGFILE.aux $LOGFILE
         echo "_SERVER_|BYE" > $fifo
         rm $fifo
      fi
   fi
}



#Capture SIGINT for a graceful stop
trap "Shutdown" 2

if [ $# -gt 2 ]
then
   echo "Uso: $0 [puerto (default 11111)]"
   exit 1
fi

if [ $# = "2" ]
then
   PUERTO=$1
else
   PUERTO=11111
fi


#clear previous sessions:
rm connection_pipe ack_pipe pids_pipe $LOGFILE s_data_pipe .conn.* 2>/dev/null
mkfifo connection_pipe ack_pipe s_data_pipe pids_pipe

./dummy connection_pipe ack_pipe s_data_pipe pids_pipe &
export DUMMY_PID=$!

cat pids_pipe > $PIDFILE &
export PIDS_PID=$!

nc -w 1 -d -l -k $PUERTO > connection_pipe &
export LISTENER_PID=$!

indexador_clientes=0;
> $LOGFILE

#Incomming connections manager
cat connection_pipe | \
    gawk -F'|' '/^conn\|[[:alpha:]]+\|[[:digit:]]+\|[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+/{print $2"_"$3"_"$4; fflush(); }' | \
    while read line
    do
       fifo=.conn.$line
       if [ -p $fifo ]
       then
          echo "Intento de reconexion denegado."
       else
          mkfifo $fifo
          ./dummy $fifo &
          registra_pid "client_dummy" "$!"
          #PIDS_CLIENTES["$fifo"]=$!

          nombre=${fifo##.conn.}
          nombre=${nombre%%_*}
          cat $fifo | \
              nc $(echo $fifo | gawk -F"_" '{print $3,$2}') | \
              gawk -v nombre=$nombre '{print nombre"|"$0; fflush()}' > s_data_pipe &
          registra_pid "client_netcat" "$!"
          
          echo "YAY" > $fifo

          add_client $nombre $fifo
          indexador_clientes=$(($indexador_clientes + 1))
       fi
    done &

export INC_CONN_HANDLER_PID=$!



    #> ack_pipe &


export CONN_PARSER_PID=$!

echo "Servidor escuchando en puerto $PUERTO"

#echo "dummy|$DUMMY_PID"              > log_pipe
#echo "netcat|$LISTENER_PID"          > log_pipe
#echo "pidder|$PIDS_PID"              > log_pipe
#echo "parser|$CONN_PARSER_PID"       > log_pipe
#echo "handler|$INC_CONN_HANDLER_PID" > log_pipe
registra_pid "dummy"   "$DUMMY_PID"             
registra_pid "netcat"  "$LISTENER_PID"         
registra_pid "pidder"  "$PIDS_PID"             
registra_pid "parser"  "$CONN_PARSER_PID"      
registra_pid "handler" "$INC_CONN_HANDLER_PID"








#while false
#do
#
#   echo "broadcasteando probes"
#   for i in  "${CLIENTES[*]}"; do echo "probe" > ${CLIENTES[$i]} ; done
#
#   sleep 1
#
#done 

rm .conv.log 2>/dev/null
mkfifo .conv.log
./dummy .conv.log &
registra_pid "dummy" "$!"
cat .conv.log > CONVERSATION &
registra_pid "cat_log" "$!"



echo "DATOS CLIENTES:"

cat s_data_pipe |  \
   tee .conv.log | \
   while read linea_chat
   do
      HACER_BCAST=true
      #linea_chat="$(echo $linea_chat | sed 's/[^[:alpha:]|[:digit:]]/ /g')"
      usuario=${linea_chat%%|*}
      texto=${linea_chat##*|}
      texto="$(echo $texto  | sed 's/[^[:alpha:]|[:digit:]]/ /g')"
      comando=${texto:0:1}
      if [ "${linea_chat##*|}" == "_BYE_" ] #algun cliente se desconecta
      then
         echo "Terminando ${linea_chat%%|_BYE_} por desconexion de usuario"
         end_client ${linea_chat%%|_BYE_}
      elif [ "${linea_chat##*|}" == "_WHO_" ] #algun cliente quiere saber los usuarios conectados
      then
         echo "Who -> ${linea_chat%%|_WHO_}"
         mandar_listado ${linea_chat%%|_WHO_}
         HACER_BCAST=false
      elif [ "$comando" == "_" -o "$comando" == "" ] #ignoramos comandos no reconocidos o ilegales y mensajes vacios
      then
         HACER_BCAST=false
      fi


      #$HACER_BCAST && broadcast $linea_chat
      $HACER_BCAST && broadcast "$usuario|$texto"
      echo "Recibido $linea_chat"
   done



#while true
#do
#   for i in  "${FIFOS_CLIENTES[*]}"
#   do
#      
#   done
#done






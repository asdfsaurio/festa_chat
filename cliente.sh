#!/bin/bash

SEQ=$(date "+%Y%m%d%H%M%S%N")
DATA_IN_PIPE=.recv_data_pipe_$SEQ
DATA_OUT_PIPE=.send_data_pipe_$SEQ
PLAYER_IN_PIPE=.player_in_pipe_$SEQ
LOGPIPE=.client_log_pipe_$SEQ
LOGFILE=log_client_$SEQ.txt

PARAMS_FILE=.$SEQ.params.txt

function print_commands()
{
   echo "Escribe un mensaje o alguno de los siguientes comandos:"
   echo "  +       : Aumenta el volumen"
   echo "  -       : Disminuye el volumen"
   echo "  _bye    : Disminuye el volumen"
   echo "  _who    : Muestra usuarios conectados"
   echo "  _whoami : Muestra nombre con el que estas conectado"
   echo "  _help   : Muestra esta pantalla"
}


function init_params()
{
   rm $PARAMS_FILE &> /dev/null
   echo "VOLUMEN|5"   >> $PARAMS_FILE
   echo "CONECTADO|0" >> $PARAMS_FILE
}

#$1 -> nombre del parametro a obtener
function get_param()
{
   [ $# = "1" ] && cat $PARAMS_FILE | grep $1 | cut -d"|" -f2
}

#$1 -> nombre del parametro a obtener
function save_param()
{
   if [ $# = "2" ]
   then
      cat $PARAMS_FILE      | \
      sed "s/$1|.*/$1|$2/g" > $PARAMS_FILE.aux

      mv $PARAMS_FILE.aux $PARAMS_FILE
   else
      echo "uso save_param <parametro> <valor>"
   fi
}


function Shutdown()
{
   save_param CONECTADO 0
   echo "_BYE_" > $DATA_OUT_PIPE
   #matar procesos del cliente
   cat $LOGFILE | gawk -F'|' '{print $2}' | xargs kill

   #borrar todo
   for i in $(ls -a | grep $SEQ)
   do
      rm $i
   done

   exit 0
}

function encolar_reproduccion()
{
   echo "$@" > $PLAYER_IN_PIPE
}

#Capturar SIGINT para parar de forma controlada
trap "Shutdown" 2


if [ $# -ne 8 ]
then
   echo "Uso: $0 -u <usuario> -i <IP_servidor> -p <puerto_servidor (def: 11111)> -P <puerto_disponible_en_esta_maquina>"
   exit 1;
fi

while getopts "u:i:p:P:" opt
do
   case $opt in
      u) USUARIO=$OPTARG
         ;;
      i) IP_SERVIDOR=$OPTARG
         ;;
      p) PUERTO_SERVIDOR=$OPTARG
         ;;
      P) PUERTO_CLIENTE=$OPTARG
         ;;
   esac
done


echo "USUARIO         =   $USUARIO"
echo "IP_SERVIDOR     =   $IP_SERVIDOR"
echo "PUERTO_SERVIDOR =   $PUERTO_SERVIDOR"
echo "PUERTO_CLIENTE  =   $PUERTO_CLIENTE"

echo "Arrancando recepcion de datos..."

init_params

#clear previous sessions, if any:
rm $DATA_IN_PIPE $DATA_OUT_PIPE $LOGPIPE $PLAYER_IN_PIPE 2>/dev/null;
mkfifo $DATA_IN_PIPE $DATA_OUT_PIPE $LOGPIPE $PLAYER_IN_PIPE;
./dummy $DATA_IN_PIPE $DATA_OUT_PIPE $LOGPIPE $PLAYER_IN_PIPE &

PID_DUMMY_RECV=$!

cat $LOGPIPE > log_client_$SEQ.txt &

echo "dummy|$PID_DUMMY_RECV" > $LOGPIPE

#Netcat que recibe DATOS del servidor:
cat $DATA_OUT_PIPE | nc -l -k $PUERTO_CLIENTE > $DATA_IN_PIPE &
echo "netcat|$!" > $LOGPIPE

echo "Intentando conectar con el servidor..."
#Intento de conexion:
for ((i=0;i<3;i++))
{
   echo "conn|$USUARIO|$PUERTO_CLIENTE|$(ifconfig eth0 2>/dev/null|awk '/inet addr:/ {print $2} /Direc. inet:/{print $2}'|sed 's/addr:\|inet://')" | nc $IP_SERVIDOR $PUERTO_SERVIDOR;
   echo "Solicitud mandada. Esperando..."

   #auto wake up from read in case it gets no response from server.
   sleep 1 && echo "_IGN_|timeout" > $DATA_IN_PIPE;

   RETORNO=$(read line < $DATA_IN_PIPE && echo $line )
   READPID=$!

   #sleep 2;
   #kill $READPID
   #YAY=$(echo $line | grep YAY)

   if [ "$RETORNO" = "YAY" ]
   then
      echo "Conectado!"
      save_param CONECTADO 1
      break
   else
      echo "Reintentando... Error = $RETORNO"
   fi
}


if [ "$RETORNO" != "YAY" ]
then
   echo "El servidor no responde. Terminando."
   Shutdown
   exit 1;
fi


# Conexion con exito:
# 1 Arrancamos el pipeo al sintetizador
while read linea_reproductor
do
   echo "$linea_reproductor" | \
   ./text2wave -scale $(get_param VOLUMEN) | \
   aplay &> /dev/null
done < $PLAYER_IN_PIPE &

# 2 Parseamos las lineas recibidas del servidor
while read linea_servidor
do
   if [ "$linea_servidor" == "_SERVER_|BYE" ]
   then
      echo "Recibido disconnect del servidor. Terminando..."
      Shutdown
      exit 1
   fi

   echo "$linea_servidor" | \
      grep -v -e ^"_IGN_|" | \
      gawk -F'|' '/^[[:alpha:]]*\|_BYE_/{ print $1" se ha desconectado"; next}
                  /^[[:alpha:]]*\|_HI_/{  print $1" ha entrado al chat"; next}
                  /_SERVER_\|_WHO_/{
                           printf "%s","Usuarios conectados: ";
                           for(i=3;i<NF-1;i++)
                              printf "%s, ", $i
                           print $(NF-1)
                           next}
                         {print $1" dice "$2}' > $PLAYER_IN_PIPE &


   echo "$linea_servidor" | \
      grep -v -e ^"_IGN_|" -e "^$USUARIO"  | \
      gawk -F'|' '/_BYE_/{print $1" se ha desconectado."; next}
                  /_HI_/{ print $1" ha entrado al chat"; next}
                  /_SERVER_\|_WHO_/{
                           printf "%s","Usuarios conectados: ";
                           for(i=3;i<NF-1;i++)
                              printf "%s, ", $i
                           print $(NF-1)
                           next}
                         {print $1": "$2}'

done < $DATA_IN_PIPE &


print_commands;

#Lectura de stdin
while read linea
do
   
   if [ "$(get_param CONECTADO)" != 1 ]
   then
      exit 1
   fi

   MANDAR=false
   case $linea in
      [-+])   VOLUMEN=$(get_param VOLUMEN)
              VOLUMEN=$(($VOLUMEN $linea 1))
              if [ "$VOLUMEN" -le 10 -a "$VOLUMEN" -ge 0 ]
              then
                 save_param "VOLUMEN" $VOLUMEN
              fi

              echo "Volumen = $(get_param VOLUMEN)"
      ;;
      "_bye") Shutdown &> /dev/null
      ;;

      "_who")  echo "_WHO_" > $DATA_OUT_PIPE
      ;;

      "_whoami")  echo "Conectado como $USUARIO"
      ;;

      _*) print_commands;
      ;;

      *) MANDAR=true
      ;;
   esac

   [ "$linea" != "" ] && $MANDAR && echo $linea > $DATA_OUT_PIPE && echo "Enviado '$linea'"
done

Shutdown &> /dev/null


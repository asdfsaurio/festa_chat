
#include <stdio.h>
       #include <sys/types.h>
              #include <sys/stat.h>
                     #include <fcntl.h>


int main(int argc, char *argv[])
{
   int i;
   int fd[256];

   for(i=1;i<argc;i++)
      fd[i] = open (argv[i],O_RDWR);

   while(1)
      sleep(6000);

   return 1;
}


#! /bin/sh

#####################################################################################
#	Copy NFS
#	CP-NFS 1.00 freeware	Copyright (c) 2013 Eli Colner
#
#	Problem: copying large numbers of files using cp over NFS dramatically crippled
#	         due to the overhead of TCP/IP per distinct file.
#
#	Solution: we create n uncompressed tar archive(s) of the files to be copied on the
#	          source side before moving over the network, we extract the archive(s) on
#	          the target and then do cleanup on both sides.
#
#	Issues:
#
######################################################################################

part_size=1073741824;   # 1GB
v="";   # verbosity
debug=false;
src="";
target="";
tmp="";

function usage() {
   echo "CP-NFS 1.00 freeware\tCopyright (c) 2013 Eli Colner";
   echo;
   echo "Usage:\t./cp-nfs.sh [options] <source> <target> [-l <bytes>] [-t <path>]";
   echo "<Options>";
   echo "\t-verbose, -v       be verbose";
   echo "\t-debug, -d         print debug statements";
   echo "<Overrides>";
   echo "\t-l <bytes>         maximum volume length of tar file(s) generated before";
   echo "\t                   copying.  Value should be less than the size of the local";
   echo "\t                   partition where your temporary directory lives.  Only one";
   echo "\t                   temporary archive will exist on your HDD at any time during";
   echo "\t                   copy.  This represents the minimum amount of local disk";
   echo "\t                   space required to complete successfully.  Can also use";
   echo "\t                   M[Bytes] or G[Bytes] (default=1G)";
   echo;
}

for (( i = 1; i<= $#; i++)); do
    eval arg=\$$i;
    case $arg in
    	-version | --version)
            echo "CP-NFS 1.00 freeware\tCopyright (c) 2013 Eli Colner";
   			echo;
            exit
            ;;
        -h | --help)
            usage;
            exit
            ;;
        -v | -verbose)
            v="v";
            ;;
        -d | -debug)
            debug=true;
            ;;
        -dv | -vd)
            debug=true;
            v="v";
            ;;
        -l)
            if [ $i -eq $# ]; then
            	echo "ERROR: max volume length [-l] is undefined";
                echo;
                usage
                exit 1;
            fi
            i=$[i+1];
            eval arg=\$$i;
            if [ "G" == "${arg##*G}G" ] || [ "g" == "${arg##*g}g" ]; then
               # GB
               gb="$arg";
               gb=${gb%%G};
               gb=${gb%%g};
               if [ "$gb" == "0" ]; then
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               elif [[ $gb =~ ^[0-9]+$ ]]; then
                  part_size=$((1073741824 * $gbf));
               else
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               fi
            elif [ "M" == "${arg##*M}M" ] || [ "m" == "${arg##*m}m" ]; then
               # MB
               mb="$arg";
               mb=${mb%%M};
               mb=${mb%%m};
               if [ "$mb" == "0" ]; then
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               elif [[ $mb =~ ^[0-9]+$ ]]; then
                  part_size=$((1048576 * $mb));
               else
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               fi
            else
               # B
               if [ "$arg" == "0" ]; then
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               elif [[ $arg =~ ^[0-9]+$ ]]; then
                  part_size=$arg;
                  if [ $debug == true ]; then
      		   		echo "set part_size=$part_size";
      			  fi
               else
                  echo "ERROR: max volume length [-l] must be a positive integer";
                  echo;
                  usage
                  exit 1;
               fi
            fi
            ;;
        *)
        	src=$arg;
        	if [ ! -d $src ]; then
      		   echo "ERROR: source directory cannot be found or is not a directory";
      		   echo;
      		   usage
      		   exit 1;
      		fi
      		if [ $i -eq $# ]; then
            	echo "ERROR: target directory is undefined";
                echo;
                usage
                exit 1;
            fi
            i=$[i+1];
            eval arg=\$$i;
            target=$arg;
            if [ ! -d $target ]; then
      		   echo "ERROR: target directory cannot be found or is not a directory";
      		   echo;
      		   usage
      		   exit 1;
      		fi
            ;;
    esac
done

available_space=$(df -b ~/flight-paths-local/ | awk '{print $4}' | tail -n 1);
if [ $part_size -gt $available_space ]; then
   echo;
   echo "WARNING: max volume length [${part_size}] is larger than available disk space.";
   echo "         You may run out of disk space during cp-nfs.  Consider changing.";
   echo;
fi

# complex switches
tar_c_switches="-c${v}f";
tar_x_switches="-x${v}f";
mv_switches="-f${v}";
rm_switches="-r${v}";
cp_switches="-n${v}";

tmp=`mktemp -dt cp-nfs` || exit 1;
tmp="${tmp}/";

if [ $debug ]; then
    echo "Copying... $src to $target in ${part_size} sized parts using $tmp";
    echo "Using tmp directory -> $tmp";
fi

for file in $src/*; do
   filename="${file}";
   filename=${filename##*/};
   if [ -d $file ]; then
      ######################
      #   COPY DIRECTORY   #
      ######################
      total_size=$(ls -la $file/* | awk '{SUM += $5} END {print SUM}');
      num_parts=$(echo "scale=1; $total_size / $part_size" | bc | awk '{if ($1 % 1 != 0) {print int($1 + 1)} else {print int($1)}}');
      num_files=$(ls -la $file/* | wc -l | awk '{gsub(/ /, ""); print}')
      files_per_part=$(echo "scale=1; $num_files / $num_parts" | bc | awk '{if ($1 % 1 != 0) {print int($1 + 1)} else {print int($1)}}')
      
      split_count=1;
      split_file_count=0;
      for subfile in $file/*; do
         if [ -f $subfile ]; then
            split_file="${tmp}${filename}_split${split_count}.tmp";
            if [ ! -f $split_file ]; then
               touch $split_file;
               if [ $debug ] && [ $split_file_count != 0 ]; then
                  echo "$split_file_count file(s)";
               fi
               if [ "$v" == "v" ]; then
                  echo ">> $split_file";
               fi
               split_file_count=0;
            fi
            echo ${subfile##*/} >> $split_file;
            split_file_count=$[$split_file_count + 1];
            if [ "$split_file_count" -eq "$files_per_part" ]; then
               split_count=$[$split_count + 1];
            fi
         fi
      done
      
      if [ $debug ] && [ $split_file_count != 0 ]; then
      	echo "$split_file_count file(s)";
      fi
      
      echo;
      
      # make target directory
      if [ "$v" == "v" ]; then
         mkdir -v $target$filename
      else
         mkdir $target$filename
      fi
      
      for tmp_file in $tmp*; do
          # tar files into tmp directory
          tar_file="${tmp_file}.tar";
          tar -C $file $tar_c_switches $tar_file --files-from $tmp_file;
          
          # move over NFS to target
	      mv $mv_switches $tar_file $target$filename;
	      # extract
	      tar -C $target$filename $tar_x_switches $target$filename/${tar_file##*/};
	      # cleanup
          rm $rm_switches $target$filename/${tar_file##*/};
      done
      
      #cleanup
      rm $rm_switches $tmp;
      
   elif [ -f $file ]; then
      ######################
      #     COPY FILE      #
      ######################
      cp $cp_switches $file $target$filename;
   fi
   echo;
done

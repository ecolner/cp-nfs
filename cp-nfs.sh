#! /bin/sh

#####################################################################################
#	Copy NFS
#	CP-NFS 2.00 freeware	Copyright (c) 2013 Eli Colner
#
#	Problem: copying large numbers of files using cp over NFS dramatically crippled
#	         due to the overhead of TCP/IP per distinct file.
#
#	Solution: we create n uncompressed tar archive(s) of the files to be copied on the
#	          source side... moving each over the network, we extract the archive(s) on
#	          the target and then do cleanup on both sides.
#
#	Performance:
#
#	Issues:
#
######################################################################################

TAR_HEADER_SIZE=512;    # tar header 512 bytes
part_size=1073741824;   # 1GB
v="";    # verbosity
a="";    # include hidden files
L="";    # follow symbolic links to final target
n="";    # don't overwrite existing files at target
debug=false;
src="";
target="";
tmp="";
tar_file="";
tar_size=0;
split_file="";

function usage() {
   echo "CP-NFS 1.00 freeware\tCopyright (c) 2013 Eli Colner";
   echo;
   echo "Usage:\t./cp-nfs.sh [options] <source> <target> [-l <bytes>] [--include-hidden]";
   echo "<Options>";
   echo "\t-verbose, -v       be verbose";
   echo "\t-debug, -d         print debug statements";
   echo "<Overrides>";
   echo "\t-l <bytes>         maximum volume length of tar file(s) generated before";
   echo "\t                   copying.  Value should be less than the size of the local";
   echo "\t                   partition where your temporary directory lives.  Only one";
   echo "\t                   temporary archive will exist on your HDD at any time during";
   echo "\t                   copy - represents the minimum amount of local disk";
   echo "\t                   space required to complete successfully.  Can also use";
   echo "\t                   M[Bytes] or G[Bytes] (default=1G)";
   echo "<Extended Options>";
   echo "\t--include-hidden	  include directory entries whose names begin with a dot (.).";
   echo "\t--follow-symlinks	follow symbolic links to final target (default=skip)";
   echo "\t--no-overwrite	  prevent overwriting files at target (default=false)";
   echo;
}

for (( i = 1; i<= $#; i++)); do
    eval arg=\$$i;
    case $arg in
    	--include-hidden)
            a="a";
            ;;
        --follow-symlinks)
            L="L";
            ;;
        --no-overwrite)
            n="n";
            ;;
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

available_space=$(df -b $src | awk '{print $4}' | tail -n 1);
if [ $part_size -gt $available_space ]; then
   echo;
   echo "WARNING: max volume length [${part_size}] is larger than local available disk space.";
   echo "         You may run out of space during cp-nfs.  See -l";
   echo;
fi

# complex switches
tar_c_switches="-c${v}f";   # [-c create] [-f file mode] [-v verbosity]
tar_x_switches="-x${v}f";   # [-x extract] [-f file mode] [-v verbosity]
mv_switches="-f${v}";       # [-f force] [-v verbosity]
rm_switches="-r${v}";       # [-r recursive subdirs] [-v verbosity]
cp_switches="-f${n}${v}";   # [-f force] [-n don't overwrite existing file] [-v verbosity]
ls_switches="-lp${a}R${L}"; # [-l long formt] [-p write '/' after dirs] [-a include hidden]
                            # [-R recursive subdirs] [-L follow symbolic links to final target]

function createTar() {
	local files=$1;
	# [LOCAL]
	# tar file(s) to tmp directory
	tar -C $src $tar_c_switches $tar_file $files;
}

function extractTar() {
	# [REMOTE]
	# move tar over NFS to target
	mv $mv_switches $tar_file "${target}cp-nfs.tar";
	# extract tar on target
	tar -C $target $tar_x_switches "${target}cp-nfs.tar";
	# delete tar on target
	rm $rm_switches "${target}cp-nfs.tar";
}

function finishSplit() {
	createTar "--files-from ${split_file}"
	rm $rm_switches $split_file;
	extractTar
}

function copyDirectory() {
	local dir=$1;        # directory
	
	# add trailing '/' if missing
	local i=$((${#dir} - 1));
	if [ ${dir:i:1} != "/" ]; then
       local dir="${dir}/";
    fi
    
	for file in $dir*; do
	   local filename="${file}";
	   local filename=${filename##*/};
	   
	   # --include-hidden
	   if [ $filename == "\.*" ] && [ $a != "a" ]; then
	      # skip hidden file
		  continue;
	   fi
	   
	   if [ -L $file ]; then
          # --follow-symlinks
          if [ $L != "L" ]; then
             #skip symbolic link
             continue;
          fi
          
          local f=$(readlink "${file}");
          if [ ! -f $f ]; then
             # skip orphan link
             continue;
	      fi
	      local file=$f;
		  local filename="${file}";
	      local filename=${filename##*/};
	   fi
	   
	   if [ -d $file ]; then
	      copyDirectory $file;
	   elif [ -f $file ]; then
          local relative_path="${dir##$src}";
          local file_path="${filename}"
          if [ "${relative_path}" != "" ]; then
             local file_path="${relative_path}${filename}";
		  fi
	   
          # make sure to respect $part_size
          local file_size=$(stat -f "%z" "${file}");
          if [ $file_size -ge $((part_size - TAR_HEADER_SIZE)) ]; then
          	# single file larger than split size... can't archive
          	if [ ! -d $target$relative_path ]; then
	          	mkdir "-p${v}" $target$relative_path
	        fi
          	cp $cp_switches $src$file_path $target$relative_path
          	continue;
          fi
          
          tar_size=$(($tar_size + $file_size));
	      if [ $tar_size -gt $((part_size - TAR_HEADER_SIZE)) ]; then
	        finishSplit
			# reset counter using last seen file size
			tar_size=$file_size;
	      fi
	      
	      # add last seen file to split list
		  if [ ! -f $split_file ]; then
  	        touch $split_file;
		  fi
		  echo "${file_path}" >> $split_file;
	   fi
	done
}

function copy() {
   	# make target directory
	if [ ! -d $target ]; then
	   if [ "$v" == "v" ]; then
		  mkdir -v $target || exit 1;
	   else
		  mkdir $target || exit 1;
	   fi
	fi
	
	# add trailing '/' if missing
	local i=$((${#src} - 1));
	if [ ${src:i:1} != "/" ]; then
       src="${src}/";
    fi
	local i=$((${#target} - 1));
	if [ ${target:i:1} != "/" ]; then
       target="${target}/";
    fi
    
   copyDirectory $src;
   
   # make sure we don't miss any
   if [ -f $split_file ]; then
      finishSplit
   fi
}

# run
if [ $debug ]; then
    echo "Copying... ${src} -> ${target}";
fi

if [ -L $src ]; then
   src=$(readlink "${src}");
fi

if [ -f $src ]; then
   ######################
   #     COPY FILE      #
   ######################
   cp $cp_switches $src $target;
   
   echo;
   echo "Done!";
   echo;
   echo "Verifying...";
   size_src=$(du -achk $src | grep total | awk '{print $1}')
   if [ -f $target ]; then
      size_target=$(du -achk $target | grep total | awk '{print $1}')
   else
      size_target=$(du -achk ${target}${src##*/} | grep total | awk '{print $1}')
   fi
   
   if [ "$size_src" == "$size_target" ]; then
      echo "SUCCESS $(($size_src * 1024)) bytes copied";
   else
      echo "FAILED - see above for reason";
   fi
   echo;
   echo;
   
elif [ -d $src ]; then
	######################
	#   COPY DIRECTORY   #
	######################
	# make working directory
    tmp=`mktemp -dt cp-nfs` || exit 1;
	tmp="${tmp}/";
	
	# set working file paths
	tar_file="${tmp}cp-nfs.tar";
	split_file="${tmp}cp-nfs.tmp";
	
	if [ debug ]; then
       echo "tmp directory: ${tmp}";
       echo "volume length: ${part_size}";
	fi
	
	copy;
	
	# delete working directory
	rm $rm_switches $tmp;
	
   echo;
   echo "Done!";
   echo;
   echo "Verifying...";
   size_src=$(du -achk $src | grep total | awk '{print $1}')
   size_target=$(du -achk $target | grep total | awk '{print $1}')
   
   if [ "$size_src" == "$size_target" ]; then
      echo "SUCCESS $(($size_src * 1024)) bytes copied";
   else
      echo "FAILED - see above for reason";
   fi
   echo;
   echo;
else
   echo "ERROR: source file is not supported type - file/directory/symlink to supported";
   exit 1;
fi
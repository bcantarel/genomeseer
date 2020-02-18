#!/bin/bash
#determine_pon.sh

usage() {
  echo "-h Help documentation for hisat.sh"
  echo "-r  --Reference Genome: GRCh38 or GRCm38"
  echo "-b  --BAM File"
  echo "-c  --Capture Bedfile"
  echo "Example: bash determine_pon.sh -r /project/shared/bicf_workflow_ref/human/GRCh38 -b SRR1551047.bam -c target.bed"
  exit 1
}
OPTIND=1 # Reset OPTIND
while getopts :r:b:p:n:f:d:t:c:uh opt
do
    case $opt in
        b) sbam=$OPTARG;;
        p) pair_id=$OPTARG;;
	r) index_path=$OPTARG;;
	u) umi='umi';;
        h) usage;;
    esac
done

shift $(($OPTIND -1))
baseDir="`dirname \"$0\"`"

if [[ -z $SLURM_CPUS_ON_NODE ]]
then
    SLURM_CPUS_ON_NODE=1
fi

source /etc/profile.d/modules.sh
module load bedtools/2.26.0

if [[ -z $index_path ]] 
then
    index_path='/project/shared/bicf_workflow_ref/human/grch38_cloud/dnaref'
fi
if [[ -z $paneldir ]] 
then
    paneldir="UTSW_V3_pancancer"
fi

capture="$paneldir/targetpanel.bed"
targets="$paneldir/cnvkit."
normals="$paneldir/pon.cnn"

if [[ $paneldir == *UTSW_V3_pancancer* ]]
then
    bedtools coverage -sorted -g  ${index_path}/genomefile.txt -a ${capture} -b ${sbam} -hist > covhist.txt
    grep ^all covhist.txt > genomecov.txt
    sumdepth=`awk '{ sum+= $2*$3;} END {print sum;}' genomecov.txt`
    total=`head -n 1 genomecov.txt |cut -f 4`
    avgdepth=$((${sumdepth}/${total}))
    if [[ "$avgdepth" -lt 1000 ]]
    then
	normals="${paneldir}/pon.downsample.cnn"
    fi
elif [[ $paneldir == *UTSW_V2_pancancer* ]] & [[ $umi == 'umi' ]]
then
    normals="${paneldir}/pon.umi.cnn"
fi

idtopt='';
if [[ $paneldir == UTSW_V4* ]]
then
    idtopt='-q'
fi

bash $baseDir/../process_scripts/variants/cnvkit.sh -r $index_path -b $sbam -p $pair_id -d $paneldir
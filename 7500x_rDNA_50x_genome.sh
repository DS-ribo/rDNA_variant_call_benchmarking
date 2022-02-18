#!/bin/bash
#SBATCH --verbose
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=
#SBATCH --time=
#SBATCH --job-name=
#SBATCH --mail-type=
#SBATCH --mail-user=
#SBATCH --output=
#SBATCH --error=

##### rDNA reads simultation and variant call at 7,500x rDNA coverage #####
# Original: Jun 2020; modified: Feb 2022                                  #
# Daniel Sultanov                                                         #
# Additional prerequisites:                                               #
# - NEAT-genReads (see 10.1371/journal.pone.0167047)                      #
# - rDNA sequence: rDNA_repeat_S288c.fsa                                  #
# - modified rDNA annotations: rDNA_repeat_S288c_benchmark.bed            #
# - "golden" set of variants (priors) variants_golden_priors.vcf          #
# - models inferred from real short-read sequencing data                  #
# (see the "Model inference" script) generated by NEAT-genReads:          #
#   -> read fragment length model: fraglen.p                              #
#   -> sequencing error model: seq_error.p                                #
#   -> G/C content model: gcmodel.p                                       #
###########################################################################

#rDNA coverage: 7,500x
#Genome coverage: 50x

##Load modules
module purge
module load numpy/python2.7/intel/1.14.0
module load samtools/intel/1.9
module load bowtie2/2.3.4.3
module load samtools/intel/1.3.1
module load lofreq_star/2.1.3.1

#Note: change paths to files|scripts|etc accordingly

##Run simulator
#Generate sequences with variants ("alternative" sequences)
#variant frequency = 0.005
#control parameters: c (38/7500 == 0.005), M, and o
python neat-genreads-master/genReads.py \
-r rDNA_repeat_S288c.fsa \
-R 150 \
-o out_7500_1 \
--bam \
--vcf \
--pe-model fraglen.p \
-e seq_error.p \
--gc-model gcmodel.p \
-p 1 \
-M 0.015 \
-c 38 \
-t rDNA_repeat_S288c_benchmark.bed \
-to 0.4 \
--rng 123

#Generate sequences  "reference" sequences
#explicitly specify -M 0 here
#change /path/to/neat-genreads-master accordingly
python neat-genreads-master/genReads.py \
-r rDNA_repeat_S288c.fsa \
-R 150 \
-o out_7500_2 \
--bam \
--pe-model fraglen.p \
-e seq_error.p \
--gc-model gcmodel.p \
-p 1 \
-M 0 \
-c 7462 \
-t rDNA_repeat_S288c_benchmark.bed \
-to 0.4 \
--rng 456

#Merge jobs
#path to samtools i.e. /share/apps/samtools/1.9/intel/bin/samtools
neat-genreads-master/mergeJobs.py -i out_7500_1 out_7500_2 -o simulation_7500 -s /path/to/samtools --no-job

##Map reads
#change /path/to/rDNA/prototype/index/prefix accordingly
bowtie2 -5 1 -N 1 -p 8 -x /path/to/rDNA/prototype/index/prefix -1 simulation_7500_read1.fq -2 simulation_7500_read2.fq -S simulation_7500_pipeline.sam
#convert to bam, sort, index
samtools view -Sbh -F 12 simulation_7500_pipeline.sam > simulation_7500_pipeline.bam
samtools sort -o simulation_7500_pipeline.sort.bam -O 'bam' simulation_7500_pipeline.bam
rm simulation_7500_pipeline.bam
samtools index simulation_7500_pipeline.sort.bam

##Call variants
lofreq indelqual --dindel -f rDNA_repeat_S288c.fsa -o simulation_7500_pipeline.dindel.bam simulation_7500_pipeline.sort.bam
lofreq call --call-indels -f rDNA_repeat_S288c.fsa -o simulation_7500_pipeline.vcf simulation_7500_pipeline.dindel.bam

##Compare two .vcf files
python neat-genreads-master/utilities/vcf_compare_OLD.py -r rDNA_repeat_S288c.fsa -g variants_golden_priors.vcf -w simulation_7500_pipeline.vcf -o simulation_7500 -a 0.002 --vcf-out --incl-fail --no-plot

mkdir simulation_7500
mv out_7500_1 simulation_7500
mv out_7500_2 simulation_7500
mv simulation_7500_* simulation_7500
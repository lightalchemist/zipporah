#!/bin/bash

config=$1
. $config

[ "$modeldir" == "" ] && modeldir=$working/$id/step-1/model

f2e=$modeldir/dict.$input_lang-$output_lang
e2f=$modeldir/dict.$output_lang-$input_lang

for data in bad dev bad.dev; do
  echo Processing $data data
  test=$working/$id/step-2/corpus/$data

  base=$working/$id/step-3/$data
  mkdir -p $base

# GENERATING TRANLSATION SCORES
###############################################################################
  echo Computing Translation Scores on $data Using Dictionaries $e2f and $f2e

  n=$bow_jobs
  tmpfolder=$base/translation/
  mkdir -p $tmpfolder

  rm $tmpfolder/ -f -r
  mkdir -p $tmpfolder

  paste $test.$input_lang $test.$output_lang > $tmpfolder/pasted
  split -a 3 -d -n l/$translation_num_jobs $tmpfolder/pasted $tmpfolder/pasted.s.

  n=$translation_num_jobs
  for i in `seq -w $[$translation_num_jobs-1] -1 0`; do
    while [ ! -f $tmpfolder/pasted.s.$i ]; do
      i=0$i
    done
    cat $tmpfolder/pasted.s.$i | awk -F '\t' '{print $1}' > $tmpfolder/s.in.$n
    cat $tmpfolder/pasted.s.$i | awk -F '\t' '{print $2}' > $tmpfolder/s.out.$n
#    mv $tmpfolder/s.in.$i $tmpfolder/s.in.$n
#    mv $tmpfolder/s.out.$i $tmpfolder/s.out.$n
    n=$[$n-1]
  done

  $ROOT/scripts/queue.pl JOB=1:$translation_num_jobs $tmpfolder/compute-kl.f2e.JOB.log $ROOT/scripts/generate-translation-scores.sh $config $tmpfolder/s.in.JOB $tmpfolder/s.out.JOB $f2e $tmpfolder/out.f2e.JOB 
  $ROOT/scripts/queue.pl JOB=1:$translation_num_jobs $tmpfolder/compute-kl.e2f.JOB.log $ROOT/scripts/generate-translation-scores.sh $config $tmpfolder/s.out.JOB $tmpfolder/s.in.JOB $e2f $tmpfolder/out.e2f.JOB

  touch $base/translation.$input_lang-$output_lang $base/translation.$output_lang-$input_lang
  rm    $base/translation.$input_lang-$output_lang $base/translation.$output_lang-$input_lang

  for i in `seq 1 $[$translation_num_jobs]`; do
    cat $tmpfolder/out.f2e.$i >> $base/translation.$input_lang-$output_lang
    cat $tmpfolder/out.e2f.$i >> $base/translation.$output_lang-$input_lang
  done

  echo Computing Ngram Scores on $data Using LM $modeldir/lm.$input_lang $modeldir/lm.$output_lang

  for lang in $input_lang $output_lang; do
  (    vocab=$modeldir/ngram/vocab.$lang
    map_unk=`tail -n 1 $vocab`

    cat $test.$lang | awk -v v=$vocab -v u=$map_unk 'BEGIN{while((getline<v)>0) m[$1]=1;}{for(i=1;i<=NF;i++) {w=$i; if(m[w] !=1) w=u; printf("%s ", w)}; print""}' | $moses/bin/query -v sentence  $modeldir/bin.lm.$lang | grep ^Total | awk '{print -$2}' > $base/ngram.total.$lang
    cat $test.$lang | awk '{print NF + 1}' > $base/ngram.length  # +1 because of the EOS symbol
    paste $base/ngram.total.$lang $base/ngram.length | awk '{print $1 / $2}' > $base/ngram.$lang
  ) 
  done
  
  wait
done

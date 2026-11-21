#!/bin/bash
# usage: bench/to_csv.sh <raw_file> <out_prefix>   ->  <out_prefix>_runs.csv, <out_prefix>_summary.csv
set -e
RAW=$1; PRE=$2

awk 'BEGIN { OFS=","; print "round,variant,impl,compiler,time_s,cycles,instructions,branches,branch_misses,ghz,temp_before_c,temp_after_c,loadavg" }
     { split($2,a,"_"); print $1,$2,a[1],a[2],$3,$4,$5,$6,$7,$8,$9,$10,(NF>=11?$11:"") }' "$RAW" > "${PRE}_runs.csv"

sort -k2,2 -k3,3n "$RAW" | awk '
{ v=$2; q=++k[v]; t[v,q]=$3; s[v]+=$3; ss[v]+=$3*$3; c[v]+=$4; n[v]+=$5; br[v]+=$6; m[v]+=$7; g[v]+=$8
  if (!(v in cm) || $4<cm[v]) cm[v]=$4 }
END {
  print "variant,impl,compiler,n,median_s,min_s,sd_s,cycles,cycles_min,instructions,ipc,branches,branch_misses,miss_rate_pct,ghz"
  for (v in k) { q=k[v]; med=(q%2)?t[v,(q+1)/2]:(t[v,q/2]+t[v,q/2+1])/2; sd=sqrt(ss[v]/q-(s[v]/q)^2); split(v,a,"_")
    printf "%s,%s,%s,%d,%.3f,%.3f,%.3f,%.0f,%.0f,%.0f,%.3f,%.0f,%.0f,%.3f,%.3f\n",
      v,a[1],a[2],q,med,t[v,1],sd,c[v]/q,cm[v],n[v]/q,n[v]/c[v],br[v]/q,m[v]/q,100*m[v]/br[v],g[v]/q } }' \
  | (read h; echo "$h"; sort -t, -k8 -n) > "${PRE}_summary.csv"

echo "${PRE}_runs.csv ${PRE}_summary.csv"

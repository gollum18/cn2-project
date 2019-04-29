#! /bin/awk -f
# This utilizes knuths method for determining variance with streamed 
#   data. The amount of data worked with here is too large to do 
#   so at the end of the script.
BEGIN { print FILENAME; n=1; m=$2; v=0 }
{ xk = $2;
  n++; 
  mo = m;
  m = mo+((xk-mo)/n); 
  v = v+(xk-mo)*(xk-m);
}
END { 
      print ("N: " n);
      print ("Average: " m); 
      print ("Variance: " v/(n-1));
      print ("Std. Dev.: " sqrt(v/(n-1)));
    }

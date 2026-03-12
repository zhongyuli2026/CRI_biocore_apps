rm(list = ls())
## --------------------------------------------------------------------------- ##
## This script is used to preapre input data tokens
## Yan Li, Oct 2025
## --------------------------------------------------------------------------- ##
library(dplyr)
data.path <- 'input_data/CRI-BIO-757_GO/allClusterPosMarkers_ovary_cpEnrich_GoSep_clustered_res_BP.txt'
filename_prefix <- 'allClusterPosMarkers_ovary_BP'
## ---
data.path <- 'input_data/CRI-BIO-757_GO/allClusterPosMarkers_ovary_cpEnrich_GoSep_clustered_res_CC.txt'
filename_prefix <- 'allClusterPosMarkers_ovary_CC'
## ---
data.path <- 'input_data/CRI-BIO-757_GO/allClusterPosMarkers_ovary_cpEnrich_GoSep_clustered_res_MF.txt'
filename_prefix <- 'allClusterPosMarkers_ovary_MF'
## ---
data.path <- 'input_data/CRI-BIO-757_Hallmark/allClusterPosMarkers_ovary_hallmark_cpEnrich_hallmark_catH_clustered_res.txt'
filename_prefix <- 'allClusterPosMarkers_ovary_hallmark'
## ---
data.path <- 'input_data/CRI-BIO-757_KEGG/allClusterPosMarkers_ovary_cpEnrich_kegg_clustered_res.txt'
filename_prefix <- 'allClusterPosMarkers_ovary_kegg'
## ---------
data <- read.delim(file = data.path)

## Split the data by the 'Cluster' column
data_by_cluster <- split(data, data$Cluster)

for(cluster_name in names(data_by_cluster)){
  cluster_data <- data_by_cluster[[cluster_name]] %>% dplyr::select(-Cluster)  
  write.table(cluster_data,
              file = file.path(dirname(data.path), paste0(filename_prefix, '_', cluster_name, ".txt")),
              sep = "\t",
              quote = FALSE,
              row.names = FALSE)
}


## --------------------------------------------------------------------------- ##

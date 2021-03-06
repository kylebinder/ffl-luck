#setwd("/home/rstudio-user/project")
#install.packages(c('data.table', 'XML', 'stringr', 'foreach', 'doSNOW'))
source('read.season.R')
source('create_all_schedules.R')
source("simulation_helper.R")
source("get.next.permutation.R")

weeks <- 2*(div.size-1) + num.teams - div.size

# read in all seasons' scores rather than just one year's
seasons <- as.data.table(read.csv(file = "league117history.csv"))
seasons <- seasons[, X:=NULL] # remove that index column
#season.dt <- get.season.scores(league.id = 117, year = 2016)[week <= weeks]

years <- seasons[, unique(year)]
# just do this one for now.
yr <- 2014

season.dt <- seasons[year==yr] 

setkeyv(season.dt, c("week", "owner"))
season.dt[, owner.id := .GRP, by=.(owner)]

season.dt <- season.dt[owner.id <= num.teams]

sched <- create.reg.season.schedule.all.teams()

season.dt <- season.dt[week <= weeks,]

# uses record counter to keep track of each team's 
record.distribution <-      
  as.data.table(expand.grid(c(1:num.teams), c(0:weeks))) 
names(record.distribution) <- c("home.owner.id", "w")
setkeyv(record.distribution, c("home.owner.id", "w"))
record.distribution$count = 0

# construct all matchups and generate perspective wins, to serve as a lookup 
all.possible.matchups <- data.table(expand.grid(1:weeks, 1:num.teams, 1:num.teams))
names(all.possible.matchups) <- c("week", "home.owner.id", "opp.owner.id")
setkeyv(all.possible.matchups, c("week", "home.owner.id"))
setkeyv(season.dt, c("week", "owner.id"))
all.possible.matchups[season.dt, home.score := score]
setkeyv(all.possible.matchups, c("week", "opp.owner.id"))
all.possible.matchups[season.dt, opp.score := score]
all.possible.matchups[, w := home.score > opp.score]
setkeyv(all.possible.matchups, c("week", "home.owner.id", "opp.owner.id"))


curr <- 1:num.teams # first permutation
j <- 0
denom <- factorial(12)
#save.image("./workspace.Rdata")    

load("breaks.Rda")

library(parallel)
cores <- detectCores()
print(try(stopCluster(cl = cl), silent = T))
cl <- makeCluster(cores, outfile="", logical=F)

curr.index <- 1:16

clusterExport(cl, "breaks")
clusterExport(cl, "get.next.permutation")
clusterExport(cl, "simulate.season")
clusterEvalQ(cl, library('data.table'))
clusterExport(cl, c("sched", "all.possible.matchups", "record.distribution", "denom"))

#initialize if need be
init <- F
if(init==T) {
  sapply(1:16, function(ci) {
    curr <- breaks[[ci]]
    stop.curr <- breaks[[ci+1]]
    j <- 0
    save(list = c('j', 'curr', 'record.distribution'),
         file=paste0("image_", ci,".Rdata"))
  })
}

do.one <- function(ci) {
  curr <- breaks[[ci]]
  stop.curr <- breaks[[ci+1]]
  j <- 0
  # for restarting
  load(file=paste0("image_", ci,".Rdata"))
  print(c(paste0(Sys.time(), ' ', ci,": ", j, ', ', round(j/denom*16*100, digits=3),"%")))
  while(j < 10000) {
  #while(!all(curr==stop.curr)){
    simulate.season(schedule = sched, 
                    ordering = curr,
                    all.possible.matchups = all.possible.matchups, 
                    rec.dist = record.distribution)
    curr <- get.next.permutation(curr, stop.curr = stop.curr)
    j <- j + 1
    # every so often, save
    if(j%%1000==0) {
      print(c(paste0(Sys.time(), ' ', ci,": ", j, ', ', round(j/denom*16*100, digits=3),"%")))
      save(list = c('j', 'curr', 'record.distribution'),
           file=paste0("image_", ci,".Rdata"))
    } 
  }
  save.image(file=paste0("image_",ci,".Rdata"))
  return(record.distribution)
}

system.time(
  results <- clusterApply(cl, 1:16, do.one)
)

stopCluster(cl)

stop()


# add back owner names
#record.distribution <- 
#  merge(x=record.distribution, y=unique(season.dt[, .(owner.id, owner)]), by = "owner.id")

#setkeyv(record.distribution, c("w", "owner.id"))
#return(record.distribution)
save(list=c("yr", "record.distribution"), file=paste0(year,"results.Rda"))
#})

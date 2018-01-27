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

# import standings
standings.dt <- load("standingsdt.Rda")

years <- seasons[, unique(year)]
# just do this one for now.
#yr <- 2016

for(yr in years) {
  standings <- get.season.standings(league.id = 117, year = yr)
  setkeyv(standings, "owner")
  
  season.dt <- seasons[year==yr] 
  
  setkeyv(season.dt, c("week", "owner"))
  season.dt[, owner.id := .GRP, by=.(owner)]
  
  season.dt <- season.dt[owner.id <= num.teams]
  
  sched <- create.reg.season.schedule.all.teams()
  
  season.dt <- season.dt[week <= weeks,]
  number.of.seasons.to.simulate <- 1024*1024
  
  # uses record accumulator to keep track of each team's 
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
  
  
  set.seed(99)
  
  system.time(
    for(ii in 1:number.of.seasons.to.simulate) {
      curr <- sample(1:12, replace = F)
      
      simulate.season(schedule = sched, 
                      ordering = curr,
                      all.possible.matchups = all.possible.matchups, 
                      rec.dist = record.distribution)
      if(ii %% 1000==0) {
        print(ii)
      }
    }
  )
  
# add back owner names
record.distribution <- 
  merge(x=record.distribution, y=unique(season.dt[, .(owner.id, owner)]),by.x="home.owner.id", by.y = "owner.id")

record.distribution[, expected.wins := sum(w*count)/sum(count), by=.(home.owner.id)]
record.distribution[, prob := count/number.of.seasons.to.simulate, by=.(owner)]
record.distribution[, cumprob := cumsum(prob), by=.(owner)]
record.distribution[, stdev := sqrt(sum(count*(w-expected.wins)^2)/number.of.seasons.to.simulate), by=.(owner)]

# attach actual wins
setkeyv(record.distribution, "owner")
record.distribution[standings, actual.wins := wins]
setkeyv(record.distribution, c("home.owner.id", "w"))
write.csv(x = record.distribution, file = paste0("rec.dist",yr,".csv"))

return(record.distribution)
}
save(list=c("yr", "record.distribution"), file=paste0(year,"results.Rda"))
#})
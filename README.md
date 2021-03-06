
<!-- README.md is generated from README.Rmd. Please edit that file -->

# nflWAR

## A Reproducible Method for Offensive Player Evaluation in Football

This package is designed to implement the estimation of [Wins Above
Replacement](https://en.wikipedia.org/wiki/Wins_Above_Replacement) for
offensive skill position players in the NFL based on the methodology
described in our paper, available on the
[arXiv](https://arxiv.org/abs/1802.00998).

## Installation

You can install `nflWAR` from github with:

``` r
# install.packages("devtools")
devtools::install_github("ryurko/nflWAR")
```

## Replacement Level Definitions

We first create the replacement level definitions using the
`create_percentage_replacement_fn` and `create_league_replacement_fn`
functions. These will give us functions to find replacement level
performances for each position. The example below creates a function to
return the replacement level QBs based on the ten percent cutoff
described in the paper, while the other positions are merely defined
based on the attempts.

``` r
library(nflWAR)
#> Loading required package: magrittr
league_replacement_functions <- list("find_replacement_QB" = create_percentage_replacement_fn("Perc_Total_Plays", .1),
                                     "find_replacement_RB_rec" = create_league_replacement_fn(3, "RB", "Targets"), 
                                     "find_replacement_WR_rec" = create_league_replacement_fn(4, "WR", "Targets"),
                                     "find_replacement_TE_rec" = create_league_replacement_fn(2, "TE", "Targets"),
                                     "find_replacement_RB_rush" = create_league_replacement_fn(3, "RB",
                                                                                               "Rush_Attempts"),
                                     "find_replacement_WR_TE_rush" = create_league_replacement_fn(1, "WR",
                                                                                                  "Rush_Attempts",
                                                                                                  combine_wrte = 1))
```

## Model Formulas

Next we initialize the two different formula lists: (1) Expected Points
Added based WAR and (2) Win Probability Added based WAR:

``` r
# Create the expected points based modula formulas:
ep_model_formula_list <- list("air_formula" = as.formula(airEPA_Result ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + QBHit + 
                                                           Receiver_Position + PassLocation + Rush_EPA_Att +
                                                           (1|Passer_ID_Name) + (1|Receiver_ID_Name) + (1|DefensiveTeam)),
                              "yac_formula" = as.formula(yacEPA_Result ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + QBHit + 
                                                           AirYards*Receiver_Position + PassLocation + Rush_EPA_Att +
                                                           (1|Passer_ID_Name) + (1|Receiver_ID_Name) + (1|DefensiveTeam)),
                              "qb_rush_formula" = as.formula(EPA ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + Pass_EPA_Att +
                                                               (1|Rusher_ID_Name) + (1|DefensiveTeam)),
                              "main_rush_formula" = as.formula(EPA ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + 
                                                                 Rusher_Position + Pass_EPA_Att +
                                                                 (1|Team_Side_Gap) + (1|Rusher_ID_Name) + (1|DefensiveTeam)))

# Create the win probability based modula formulas:
wp_model_formula_list <- list("air_formula" = as.formula(airWPA_Result ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + QBHit + 
                                                           Receiver_Position + PassLocation + Rush_EPA_Att +
                                                           (1|Passer_ID_Name) + (1|Receiver_ID_Name) + (1|DefensiveTeam)),
                              "yac_formula" = as.formula(yacWPA_Result ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + QBHit + 
                                                           AirYards*Receiver_Position + PassLocation + Rush_EPA_Att +
                                                           (1|Passer_ID_Name) + (1|Receiver_ID_Name) + (1|DefensiveTeam)),
                              "qb_rush_formula" = as.formula(WPA ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + Pass_EPA_Att +
                                                               (1|Rusher_ID_Name) + (1|DefensiveTeam)),
                              "main_rush_formula" = as.formula(WPA ~ Home_Ind + Shotgun_Ind + No_Huddle_Ind + 
                                                                 Rusher_Position + Pass_EPA_Att +
                                                                 (1|Team_Side_Gap) + (1|Rusher_ID_Name) + (1|DefensiveTeam)))
```

## WAR Pipeline

The code below demonstrates the `nflWAR` pipeline for both types of WAR
estimates to generate the results in our paper. This pipeline is
intended to be modular and will continue to be improved with package
development.

``` r
# Just a good idea to install the tidyverse if you don't have it, we use purrr for below:
# install.packages("tidyverse")
library(tidyverse)

# Apply the pipeline of functions to the given year and save the data using the WPA based model for 
# estimating WAR and also join all of the standard statistics for players.
# (Modify the saveRDS file path for your destination)

# First WPA based WAR:
walk(c(2009:2017), function(x) {
  season_results <- x %>% 
    get_pbp_data() %>%
    add_positions(x) %>%
    add_model_variables() %>%
    prepare_model_data() %>%
    add_position_tables() %>%
    join_position_statistics() %>%
    find_positional_replacement_level(league_replacement_functions) %>%
    estimate_player_value_added(wp_model_formula_list) %>%
    calculate_above_replacement() %>%
    convert_prob_to_wins()
  
  saveRDS(season_results, file = paste("wpa_model_results_", as.character(x), ".rds", sep = ""))
})
  
# EPA based WAR
walk(c(2009:2017), function(x) {
  season_results <- x %>% 
    get_pbp_data() %>%
    add_positions(x) %>%
    add_model_variables() %>%
    prepare_model_data() %>%
    add_position_tables() %>%
    find_positional_replacement_level(league_replacement_functions) %>%
    estimate_player_value_added(ep_model_formula_list) %>%
    calculate_above_replacement() %>%
    convert_points_to_wins(calculate_points_per_win(x))
  
  saveRDS(season_results, file = paste("epa_model_results_", as.character(x), ".rds", sep = ""))
})
```

## Simulations

The following code demonstrates how the simulations were conducted in
the paper, note this can take quite some time to run. Will improve
example below later on for runtime enhancements.

``` r
# Create simulation results for each year with the appropriate
# pipeline that relies on the already found replacement level
# players, doing so for the WPA based model (and other typical
# statistics):

walk(c(2009:2017), function(x) {
  # Load the stored season results (modify for your file path)
  season_results <- readRDS(paste("wpa_model_results_", as.character(x), ".rds", sep = ""))
  
  # Create the pipeline expression to get the results in a simulation by resampling
  # at the drive level:
  generate_war_results <- . %>%
    resample_season(drive_level = 1) %>%
    prepare_model_data() %>%
    add_position_tables() %>%
    add_replacement_level_sim(season_results) %>%
    join_position_statistics() %>%
    estimate_player_value_added(wp_model_formula_list, return_models = 0) %>%
    calculate_above_replacement() %>%
    convert_prob_to_wins()
    
  # Simulate the results:
  sim_results <- x %>%
    get_pbp_data() %>%
    add_positions(x) %>%
    add_model_variables() %>%
    simulate_season_statistics(1000, generate_war_results) %>%
    combine_simulations()
  
  # Save 
  saveRDS(sim_results, file = paste("wpa_model_play_sim_results_", as.character(x), ".rds", sep = ""))
  print(paste("Finished simulation for year ", as.character(x), sep = ""))
})
```

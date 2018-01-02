#' Retrieves nflscrapR Play-by-Play Data
#'
#' @param years Single number or vector of years to get play-by-data for.
#' @param live Indicator for whether or not to scrape the data or access
#'             saved files on github. Defaults to FALSE.
#' @return Data frame of the play-by-play for the given year(s).
#' @examples
#' # Get data from 2009 to 2016:
#' pbp_df <- get_pbp_data(c(2009:2016))
#' @export

get_pbp_data <- function(years, live = FALSE) {
  purrr::map_dfr(years, function(x) {
    suppressMessages(readr::read_csv(paste("https://raw.github.com/ryurko/nflscrapR-data/master/data/season_play_by_play/pbp_",
                           x, ".csv", sep = "")))
    }) %>% return
}

#' Adds Player Positions to Play-by-Play Data
#'
#' @param pbp_df Play-by-play data frame.
#' @param years Single number or vector of years to get team rosters for.
#' @return Play-by-play data frame with the following columns added:
#' \itemize{
#' \item{"Passer_ID_Name"} - Name and ID of the passer
#' \item{"Receiver_ID_Name"} - Name and ID of the receiver
#' \item{"Rusher_ID_Name"} - Name and ID of the rusher
#' \item{"Passer_Position"} - Position of the passer
#' \item{"Receiver_Position"} - Position of the receiver
#' \item{"Rusher_Position"} - Position of the rusher
#' }
#' @examples
#' # Add positions for data from 2009 to 2016:
#' pbp_df <- pbp_df %>% add_positions(c(2009:2016))
#' @export

add_positions <- function(pbp_df, years) {

  # Check to see if any of the plays are in 2016,
  # if so then change JAC to JAX for both sides of the ball:
  if (any(pbp_df$Season == 2016)) {
    pbp_df$posteam[which(pbp_df$posteam == "JAC" & pbp_df$Season == 2016)] <- "JAX"
    pbp_df$DefensiveTeam[which(pbp_df$DefensiveTeam == "JAC" & pbp_df$Season == 2016)] <- "JAX"
  }

  # Define a function to find the common name for a player:
  find_player_name <- function(player_names){
    if (length(player_names)==0){
      result <- "None"
    } else{
      table_name <- table(player_names)
      result <- names(table_name)[which.max(table_name)]
    }
    return(result)
  }

  # Create a table of passer names:
  passer_names <- pbp_df %>% dplyr::group_by(Passer_ID) %>%
    dplyr::summarise(Passer_Name = find_player_name(Passer[which(!is.na(Passer))])) %>%
    dplyr::ungroup()

  # Receiver names:
  receiver_names <- pbp_df %>% dplyr::group_by(Receiver_ID) %>%
    dplyr::summarise(Receiver_Name = find_player_name(Receiver[which(!is.na(Receiver))])) %>%
    dplyr::ungroup()

  # Rusher names:
  rusher_names <- pbp_df %>% dplyr::group_by(Rusher_ID) %>%
    dplyr::summarise(Rusher_Name = find_player_name(Rusher[which(!is.na(Rusher))])) %>%
    dplyr::ungroup()

  # Left join these columns:
  pbp_df <- pbp_df %>% dplyr::left_join(passer_names, by="Passer_ID") %>%
    dplyr::left_join(receiver_names, by="Receiver_ID") %>%
    dplyr::left_join(rusher_names, by="Rusher_ID")

  # Create Passer_ID_Name and Receiver_ID_Name columns joining the two together:
  pbp_df <- pbp_df %>% dplyr::mutate(Passer_ID_Name = paste(Passer_Name,Passer_ID,sep="-"),
                                     Receiver_ID_Name = paste(Receiver_Name,Receiver_ID,sep="-"),
                                     Rusher_ID_Name = paste(Rusher_Name,Rusher_ID,sep="-"))

  # Include sacks in rushes and populate the Rusher_Name and Rusher_ID_Name
  # with the Passer fields for sacks:
  pbp_df$Rusher_ID <- ifelse(pbp_df$PlayType == "Sack",
                             pbp_df$Passer_ID,
                             pbp_df$Rusher_ID)
  pbp_df$Rusher_Name <- ifelse(pbp_df$PlayType == "Sack",
                               pbp_df$Passer_Name,
                               pbp_df$Rusher_Name)
  pbp_df$Rusher <- ifelse(pbp_df$PlayType == "Sack",
                          pbp_df$Passer,
                          pbp_df$Rusher)
  pbp_df$Rusher_ID_Name <- ifelse(pbp_df$PlayType == "Sack",
                                  pbp_df$Passer_ID_Name,
                                  pbp_df$Rusher_ID_Name)

  # Create a data frame with the team rosters for the given years
  # and then filter down to only the offense skill positions,
  # selecting the necessary columns:
  team_rosters <- purrr::map_dfr(years, function(x) {
    suppressMessages(readr::read_csv(paste("https://raw.github.com/ryurko/nflscrapR-data/master/data/team_rosters/team_",
                                           x, "_rosters.csv", sep = "")))
    }) %>%
    dplyr::filter(Pos %in% c("TE","FB","WR","RB","QB")) %>%
    dplyr::select(name, Season, Team, Pos)

  # Make three versions of the rosters for each type of player:
  passer_pos <- team_rosters %>% dplyr::rename(Passer_Position_1=Pos) %>% dplyr::distinct()
  receiver_pos <- team_rosters %>% dplyr::rename(Receiver_Position_1=Pos) %>% dplyr::distinct()
  rusher_pos <- team_rosters %>% dplyr::rename(Rusher_Position_1=Pos) %>% dplyr::distinct()

  # Left join the position columns based on the player's name, team, and current season:
  pbp_df <- pbp_df %>%
            dplyr::left_join(passer_pos,
                             by = c("posteam"="Team",
                                    "Passer_Name"="name",
                                    "Season")) %>%
            dplyr::left_join(receiver_pos,
                             by = c("posteam"="Team",
                                    "Receiver_Name"="name",
                                    "Season")) %>%
            dplyr::left_join(rusher_pos,
                             by = c("posteam"="Team",
                                    "Rusher_Name"="name",
                                    "Season"))

  # Rename the position table position columns for joining again on a different column:
  passer_pos <- passer_pos %>% dplyr::rename(Passer_Position_2=Passer_Position_1)
  receiver_pos <- receiver_pos %>% dplyr::rename(Receiver_Position_2=Receiver_Position_1)
  rusher_pos <- rusher_pos %>% dplyr::rename(Rusher_Position_2=Rusher_Position_1)

  # Left join the position columns based on the player's name from the play-by-play:
  pbp_df <- pbp_df %>%
    dplyr::left_join(passer_pos,
                     by = c("posteam"="Team",
                            "Passer"="name",
                            "Season")) %>%
    dplyr::left_join(receiver_pos,
                     by = c("posteam"="Team",
                            "Receiver"="name",
                            "Season")) %>%
    dplyr::left_join(rusher_pos,
                     by = c("posteam"="Team",
                            "Rusher"="name",
                            "Season"))

  # Rename again to join without matching the team:
  passer_pos <- passer_pos %>% dplyr::rename(Passer_Position_3=Passer_Position_2)
  receiver_pos <- receiver_pos %>% dplyr::rename(Receiver_Position_3=Receiver_Position_2)
  rusher_pos <- rusher_pos %>% dplyr::rename(Rusher_Position_3=Rusher_Position_2)

  # Left join the position columns based on the player's name from the play-by-play:
  pbp_df <- pbp_df %>%
    dplyr::left_join(passer_pos,
                     by = c("Passer"="name",
                            "Season")) %>%
    dplyr::left_join(receiver_pos,
                     by = c("Receiver"="name",
                            "Season")) %>%
    dplyr::left_join(rusher_pos,
                     by = c("Rusher"="name",
                            "Season"))

  # Now choose which one to use based on which is not NA:
  pbp_df$Passer_Position <- ifelse(!is.na(pbp_df$Passer_Position_1),
                                   pbp_df$Passer_Position_1,
                                   ifelse(!is.na(pbp_df$Passer_Position_2),
                                          pbp_df$Passer_Position_2,
                                          pbp_df$Passer_Position_3))

  pbp_df$Receiver_Position <- ifelse(!is.na(pbp_df$Receiver_Position_1),
                                     pbp_df$Receiver_Position_1,
                                     ifelse(!is.na(pbp_df$Receiver_Position_2),
                                            pbp_df$Receiver_Position_2,
                                            pbp_df$Receiver_Position_3))

  pbp_df$Rusher_Position <- ifelse(!is.na(pbp_df$Rusher_Position_1),
                                   pbp_df$Rusher_Position_1,
                                   ifelse(!is.na(pbp_df$Rusher_Position_2),
                                          pbp_df$Rusher_Position_2,
                                          pbp_df$Rusher_Position_3))

  # Drop the unnecessary columns and return:
  pbp_df %>% dplyr::select(-Rusher_Position_1, -Rusher_Position_2, -Rusher_Position_3,
                           -Passer_Position_1, -Passer_Position_2, -Passer_Position_3,
                           -Receiver_Position_1, -Receiver_Position_2, -Receiver_Position_3,
                           -Passer_Name, -Receiver_Name, -Rusher_Name) %>%
    return
}

#' Adds Additional Model Variables to Play-by-Play Data
#'
#' @param pbp_df Play-by-play data frame.
#' @return Play-by-play data frame with the following columns added:
#' \itemize{
#' \item{"Shotgun_Ind"} - Indicator whether or not the play was in shotgun.
#' \item{"No_Huddle_Ind"} - Indicator whether or not the play was no huddle.
#' \item{"Home_Ind"} - Indicator whether or not the possession team was home.
#' \item{"airEPA_Result"} - airEPA for complete passes and EPA for incomplete.
#' \item{"airWPA_Result"} - airWPA for complete passes and WPA for incomplete.
#' \item{"yacEPA_Result"} - yacEPA for complete passes and EPA for incomplete.
#' \item{"yacWPA_Result"} - yacWPA for complete passes and WPA for incomplete.
#' \item{"Team_Side_Gap"} - Combine the team, side, and run gap for O-line proxy
#' }
#' @examples
#' # Add model variables:
#' pbp_df <- pbp_df %>% add_model_variables()
#' @export

add_model_variables <- function(pbp_df) {
  # Create the additional model variables and return:
  pbp_df %>% dplyr::mutate(Shotgun_Ind = as.numeric(grepl("Shotgun", desc)),
                           No_Huddle_Ind = as.numeric(grepl("No Huddle", desc)),
                           Home_Ind = ifelse(posteam == HomeTeam, 1, 0),
                           airEPA_Result = ifelse(Reception == 1, airEPA, EPA),
                           airWPA_Result = ifelse(Reception == 1, airWPA, WPA),
                           yacEPA_Result = ifelse(Reception == 1, yacEPA, EPA),
                           yacWPA_Result = ifelse(Reception == 1, yacWPA, WPA),
                           RunGap = ifelse(RunLocation == "middle", "center", RunGap),
                           Team_Side_Gap = paste(posteam, RunLocation, RunGap, sep = "-")) %>%
    return
}

#' Filter the Play-by-Play Data to Data for Modeling
#'
#' @param pbp_df Play-by-play data frame.
#' @return List of two data frames: (1) passing play-by-play
#' data, and (2) rushing play-by-play data that has been
#' filtered to only include plays used for modeling.
#' @examples
#' # Create list of model data:
#' model_data_list <- pbp_df %>% prepare_model_data()
#' @export

prepare_model_data <- function(pbp_df) {

  # Create datasets that are only passing plays and rushing plays
  # with EPA calculations:
  pass_pbp_df <- pbp_df %>% dplyr::filter(PlayType == "Pass",
                                          !is.na(airEPA_Result),
                                          !is.na(airWPA_Result),
                                          !is.na(yacEPA_Result),
                                          !is.na(yacWPA_Result),
                                          !is.na(PassLocation),
                                          !is.na(Receiver_Position),
                                          !is.na(Passer_Position),
                                          !is.na(Passer_ID_Name),
                                          !is.na(Receiver_ID_Name),
                                          Receiver_ID != "None",
                                          Passer_ID != "None",
                                          Passer_Position == "QB",
                                          Receiver_Position != "QB")

  rush_pbp_df <- pbp_df %>% dplyr::filter(PlayType %in% c("Run","Sack"),
                                          !is.na(EPA),
                                          !is.na(WPA),
                                          !is.na(Team_Side_Gap),
                                          !is.na(Rusher_Position),
                                          !is.na(Rusher_ID_Name))

  return(list("pass_model_df" = pass_pbp_df,
              "rush_model_df" = rush_pbp_df))
}

#' Creates Summary of Team Games
#'
#' @param years Single number or vector of years to get team rosters for.
#' @return Data frame with a row every team's record and score differential
#' in each of the given years.
#' @examples
#' # Summary of team performances in 2009:
#' season_summary_09 <- get_season_summary(2009)
#' @export

get_season_summary <- function(years) {
  # Create a data frame with the games data frames for the
  # given years from the nflscrapR-data repository:
  games_df <- purrr::map_dfr(years, function(x) {
    suppressMessages(readr::read_csv(paste("https://raw.github.com/ryurko/nflscrapR-data/master/data/season_games/games_",
                                           x, ".csv", sep = "")))
  })

  # Create a column, Winner for the games_data, that allows for tied games,
  # as well as score differential columns for both home and away:
  games_df <- games_df %>% dplyr::mutate(Winner = ifelse(homescore > awayscore,
                                                         home, ifelse(homescore < awayscore,
                                                               away, "TIE")),
                                         homescore_diff = homescore - awayscore,
                                         awayscore_diff = awayscore - homescore)

  # Now create two datasets, one where it's just the teams and winner,
  # the other with the scores, and gather so home and away are two rows
  # rather than two columns - to then join back together:

  games_team_df <- games_df %>%
    dplyr::select(GameID, home, away, Season, Winner) %>%
    tidyr::gather(Team_Loc,Team, -GameID, -Season, - Winner) %>%
    dplyr::arrange(GameID)

  games_score_df <- games_df %>%
    dplyr::select(GameID, homescore_diff, awayscore_diff, Season, Winner) %>%
    tidyr::gather(Team_Loc,Score_Diff, -GameID, -Season, - Winner) %>%
    dplyr::arrange(GameID) %>%
    dplyr::mutate(Team_Loc = ifelse(Team_Loc == "homescore_diff",
                                    "home", "away"))

  # Join together, create an indicator column for the winner:
  games_team_score_df <- games_team_df %>%
    dplyr::left_join(games_score_df,by = c("GameID","Season","Winner","Team_Loc")) %>%
    dplyr::mutate(Win_Ind = ifelse(Team == Winner, 1, 0))

  # Check to see if any of the plays are in 2016,
  # if so then change JAC to JAX for both sides of the ball:
  if (any(games_team_score_df$Season == 2016)) {
    games_team_score_df$Team[which(games_team_score_df$Team == "JAC" & games_team_score_df$Season == 2016)] <- "JAX"
  }

  # Group by the Season and Team columns to generate the dataframe for the analysis:
  season_team_summary <- games_team_score_df %>%
    dplyr::group_by(Season, Team) %>%
    dplyr::summarise(Wins = sum(Win_Ind), Total_Score_Diff = sum(Score_Diff)) %>%
    return
}
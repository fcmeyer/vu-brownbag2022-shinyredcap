#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

# Load required libraries ======================================================

library(shiny)
library(tidyverse)
library(plotly)

# Helper functions =============================================================

# download the full dataset, convert to a tibble,
# using the API url + keys in your .Renviron
get_redcap_data <- function() {
  REDCapR::redcap_read(
    redcap_uri = Sys.getenv('REDCAP_API_URL_VU'),
    token = Sys.getenv('REDCAP_API_KEY_VU_SUPERFAKE')
  )$data %>% tibble()
}

# removes some incomplete surveys
# uses the preappt_survey_complete variable (2 = yes)
clean_redcap_data <- function(redcap_records_table) {
  redcap_records_table %>%
    filter(preappt_survey_complete == 2) %>% # so we dont get unfinished ones
    mutate(pt_initials = pt_initials %>% # clean out initials
             toupper() %>% # capitalize (in case of, e.g. Fm or fM)
             str_replace_all('\\.','') # remove dots (if they do F.M.)
           ) 
}

# User Interface ===============================================================

# Define UI for application that draws a histogram
ui <- fluidPage(
  
  titlePanel("Patient questionnaire data"),
  sidebarLayout(
    sidebarPanel(
      actionButton(
        inputId = 'button_load',
        label = 'Load data from REDCap'
      ),
      uiOutput('patient_selector')
    ),
    mainPanel(
      fluidRow(
        h2('Hello!'),
        plotly::plotlyOutput('phq_gad')
      )
    )
  )
)

# Server back-end ==============================================================

# Define server logic required to draw a histogram
server <- function(input, output) {
  
  # Load data and save it to wrapper function once "Start" button is pressed
  data <- eventReactive(
    input$button_load,
    {
      message('getting data')
      # this uses the helper functions defined above
      get_redcap_data() %>% clean_redcap_data()
    }
  )
  
  # Dynamically render a drop-down list with all patients who are available
  output$patient_selector <- renderUI(
    {
      req(data()) # this tells shiny not to try to compute this till data is
                  # ready
      
      # Here I am dynamically generating a list of unique patient initials
      # based on the REDCap data I downloaded
      valid_patient_ids <- data() %>% 
        pull(pt_initials) %>%
        unique() # character vector with unique initial combinations
      
      selectInput(
        inputId = "patient_id",
        label = "Patient", 
        choices = valid_patient_ids
      )
    }
  )
  
  # Render my plot!
  output$phq_gad <- renderPlotly(
    {
      req(input$patient_id) # this tells shiny not to try to compute this till a patient input is provided!
      
      message(glue::glue("You chose: {input$patient_id}"))
      
      # subset data to include only stuff for this patient
      filtered_data <- data() %>% 
        filter(pt_initials == input$patient_id) %>% # IMPORTANT! filter based onm active input choice
        select(pt_initials, date_time,
               phq9_total_score, sc_tot_score) %>%
        drop_na() %>%
        pivot_longer(cols = c('phq9_total_score','sc_tot_score'),
                     names_to = 'scale',
                     values_to = 'total_score')
      
      # make the plot using ggplot arguments
      plt <- filtered_data %>% 
        mutate(scale = factor(scale) %>%
                 fct_recode("PHQ-9 Total" = 'phq9_total_score',
                            "GAD-7 Total" = 'sc_tot_score')) %>%
        ggplot(aes(x=date_time, y=total_score, color=scale)) +
        geom_line() +
        geom_point() +
        ylim(0,23) + # based on PHQ-9 limits
        geom_hline(yintercept=10, linetype='dotted') +
        labs(x='Date', y='Score', 
             color = 'Scale',
             title='Self-report scale scores') +
        theme(legend.position = 'top') +
        scale_colour_brewer(palette = "Set1")
      
      # render with the power of plotly!! :) 
      ggplotly(plt)
    }
  )
}

# Run the application===========================================================

shinyApp(ui = ui, server = server)

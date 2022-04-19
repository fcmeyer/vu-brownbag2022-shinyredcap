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
library(shinydashboard)
library(shinyWidgets)
library(tidyverse)
library(plotly)
require(tidyquant) # for moving average

# Helper functions =============================================================

# download the full dataset, convert to a tibble,
# using the API url + keys in your .Renviron
get_redcap_data <- function() {
  REDCapR::redcap_read(
    redcap_uri = Sys.getenv('REDCAP_API_URL_VU'),
    token = Sys.getenv('REDCAP_API_KEY_VU')
  )$data %>% tibble()
}

# removes some incomplete surveys
# uses the preappt_survey_complete variable (2 = yes)
clean_redcap_data <- function(redcap_records_table) {
  redcap_records_table %>%
    filter(preappt_survey_complete == 2) %>%
    mutate(pt_initials = pt_initials %>% # clean out initials
             toupper() %>% # capitalize (in case of, e.g. Fm or fM)
             str_replace_all('\\.','') # remove dots (if they do F.M.)
           ) 
}

# for getting the data in long format, so its ready for our plot
prep_data_for_plot <- function(redcap_records_table, pt_initials) {
  redcap_records_table %>%
    filter(pt_initials == pt_initials)
}

# for styling outputs. assumes that pt_initials, date_time are the only non-
# questionnaire responses, and that values range from 0 to 3.
# see https://rstudio.github.io/DT/010-style.html for more info on this code
style_dt <- function(dt) {
  vars_to_style <- names(dt)[!(names(dt) %in% c('pt_initials','date_time')) & 
                               str_ends(names(dt),'_score',negate=TRUE) # do not format total score
                             ]
  
  brks <- 0:3
  clrs <- round(seq(255, 40, length.out = length(brks) + 1), 0) %>%
    {paste0("rgb(255,", ., ",", ., ")")}
  
  dt %>%
    DT::datatable() %>%
    DT::formatStyle(vars_to_style,
                    backgroundColor = DT::styleInterval(brks,clrs)) 
}


# User Interface ===============================================================

# Define UI for application that draws a histogram
ui <- dashboardPage(
  dashboardHeader(title='Patient questionnaires'),
  dashboardSidebar(
    br(),
    actionButton(
      inputId = 'button_load',
      label = 'Start'
    ),
    uiOutput('patient_selector'),
    radioGroupButtons(
      inputId = "plot_mode",
      label = "Plotting",
      choices = c("Raw values", 
                  "Smoothed"),
      selected = 'Raw values',
      status = "primary",
      checkIcon = list(
        yes = icon("ok", 
                   lib = "glyphicon"),
        no = icon("remove",
                  lib = "glyphicon"))
    )
  ),
  dashboardBody(
    fluidRow(
      box(
        title='Plot',
        status='primary',
        solidHeader=TRUE,
        width=12,
        plotlyOutput('phq_gad')
        )
    ),
    fluidRow(
      tabBox(
        title='Questionnaire responses',
        width=12,
        tabPanel(
          'PHQ-9',
          DT::DTOutput('phq9_table')
        ),
        tabPanel(
          'GAD-7',
          DT::DTOutput('gad7_table')
        )
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
      # this uses the helper functions defined above
      get_redcap_data() %>% clean_redcap_data()
    }
  )
  
  # Define a list of available patients to select from
  available_patients <- reactive(
    {
      req(data()) # this tells shiny not to try to compute this till data is
                  # ready
      data() %>% 
        pull(pt_initials) %>%
        unique() # character vector with unique initial combinations
    }
  )
  
  # Dynamically render a drop-down list with all patients who are available
  output$patient_selector <- renderUI(
    {
      req(available_patients) 
      
      pickerInput(
        inputId = "patient_id",
        label = "Patient", 
        choices = available_patients(),
        options = list(
          `live-search` = TRUE)
      )
    }
  )
  
  output$phq_gad <- renderPlotly(
    {
      req(input$patient_id)
      message(input$patient_id)
      
      # subset data to include only stuff for this patient
      filtered_data <- data() %>% 
        filter(pt_initials == input$patient_id) %>%
        select(record_id, date_time, pt_initials, 
               phq9_total_score, sc_tot_score) %>%
        drop_na() %>%
        pivot_longer(cols = c('phq9_total_score','sc_tot_score'),
                     names_to = 'scale',
                     values_to = 'total_score') 
      
      # make the plot!
      plt <- filtered_data %>% 
        mutate(scale = factor(scale) %>%
                 fct_recode("PHQ-9 Total" = 'phq9_total_score',
                            "GAD-7 Total" = 'sc_tot_score')) %>%
        ggplot(aes(x=date_time, y=total_score, color=scale)) 
      
      if (input$plot_mode == 'Smoothed') {
        plt <- plt + geom_smooth(se=FALSE)
      } else {
        plt <- plt +
          geom_line() +
          geom_point()
      }
      
      plt <- plt + 
        ylim(0,23) + # based on PHQ-9 limits
        geom_hline(yintercept=10, linetype='dotted') +
        labs(x='Date', y='Score', 
             color = 'Scale',
             title='Self-report scale scores') +
        theme(legend.position = 'top') +
        scale_colour_brewer(palette = "Set1")
      
      ggplotly(plt)
    }
  )
  
  output$phq9_table <- DT::renderDataTable(
    {
      # subset data to include only stuff for this patient
      filtered_data <- data() %>% 
        filter(pt_initials == input$patient_id) %>%
        select(pt_initials, date_time, 
               phq9_1,phq9_2,phq9_3,phq9_4,phq9_5,phq9_6,
               phq9_7,phq9_8,phq9_9) %>%
        style_dt() # make it nicer using function defined above.
    }
  )
  
  output$gad7_table <- DT::renderDataTable(
    {
      # subset data to include only stuff for this patient
      filtered_data <- data() %>% 
        filter(pt_initials == input$patient_id) %>%
        select(pt_initials, date_time, 
               sc_gad1,sc_gad2,sc_gad3,sc_gad4,
               sc_gad5,sc_gad7) %>%
        style_dt() # make it nicer using function defined above.
    }
  )
}

# Run the application===========================================================

shinyApp(ui = ui, server = server)

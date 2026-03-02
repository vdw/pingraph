# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "chart.js", to: "https://esm.sh/chart.js@4.4.7?bundle"
pin_all_from "app/javascript/controllers", under: "controllers"

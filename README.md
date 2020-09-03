## Installation

Requirements:
* Postgresql service running
* Heroku CLI client installed.
  `brew install heroku`
* Github account with SSH configured
* gh install
  `brew install gh`

Useage:
Create a '~/.railsrc' file and add the following:

```
--database=postgresql
--template=https://raw.githubusercontent.com/stephaneliu/rails-template/master/template.rb

TODO
* Use gh api to create RAILS_MASTER_KEY, HEROKU_API_KEY secret

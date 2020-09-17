## Installation

Requirements:
* Postgresql installed and running
* Github account 
* Heroku CLI client installed.
  `brew install heroku`
* gh install
  `brew install gh`

Useage:
Create a '~/.railsrc' file and add the following:

```
--database=postgresql
--template=https://raw.githubusercontent.com/stephaneliu/rails-template/master/template.rb

TODO
* Use gh api to create RAILS_MASTER_KEY, HEROKU_API_KEY secret

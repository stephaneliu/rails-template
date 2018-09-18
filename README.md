## Installation

Requirements:
* Postgresql service running
* Heroku CLI client installed
* Gitlab account with ssh key configured

Create a '~/.railsrc' file and add the following:

```
--database=postgresql
--template=https://raw.githubusercontent.com/stephaneliu/rails-template/master/template.rb

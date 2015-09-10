gulp = require 'gulp'
glut = require 'glut'

coffee = require 'gulp-coffee'
coffeeAmdify = require 'glut-coffee-amdify'

glut gulp,
  tasks:
    coffee:
      runner: coffee
      src: 'src/**/*.coffee'
      dest: 'lib'
    components:
      runner: coffeeAmdify
      src: 'src/components/**/*.coffee'
      dest: 'public/components'

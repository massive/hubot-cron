# Description:
#   register cron jobs to schedule messages on the current channel
#
# Commands:
#   hubot add job "<crontab format>" <message> - Schedule a cron job to say something
#   hubot add event "<crontab format>" <event> <params_as_json> - Schedule a cron job to emit an event
#   hubot list jobs - List current cron jobs
#   hubot remove job <id> - remove job
#
# Author:
#   miyagawa

cronJob = require('cron').CronJob

JOBS = {}

createNewJob = (robot, pattern, user, payload, type = "message") ->
  id = Math.floor(Math.random() * 1000000) while !id? || JOBS[id]
  if type == "message" || type == "event"
    job = registerNewJob robot, id, pattern, user, payload, type
  else
    robot.send "Invalid job type #{type}"
  robot.brain.data.cronjob[id] = job.serialize()
  id

registerNewJob = (robot, id, pattern, user, payload, type = "message") ->
  JOBS[id] = new Job(id, pattern, user, payload, type)
  JOBS[id].start(robot)
  JOBS[id]

module.exports = (robot) ->
  robot.brain.on 'loaded', =>
    robot.brain.data.cronjob or= {}
    for own id, job of robot.brain.data.cronjob
      continue if JOBS[id]
      robot.logger.info "Job #{job[3]} #{id}: \"#{job[0]}\" on #{job[1].flow} #{JSON.stringify(job[2])}"
      registerNewJob(robot, id, job[0], job[1], job[2], job[3])

  robot.respond /(?:new|add) event "(.*?)" (.+?)(\s(.*))?$/i, (msg) ->
    try
      data = event: msg.match[2].trim(), payload: msg.match[4]?.trim()
      user = msg.message.user
      id = createNewJob robot, msg.match[1], user, data, "event"
      msg.send "Event job #{id} created to #{user?.flow}"
    catch error
      msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

  robot.respond /(?:new|add) job "(.*?)" (.*?)$/i, (msg) ->
    try
      user = msg.message.user
      id = createNewJob robot, msg.match[1], user, msg.match[2], "message"
      msg.send "Job #{id} created to #{user?.flow}"
    catch error
      msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

  robot.respond /(?:list|ls) jobs?/i, (msg) ->
    for own id, job of robot.brain.data.cronjob
      msg.send "Job #{id}: \"#{job[0]}\" on #{job[1].flow} \"#{JSON.stringify(job[2])}\""

  robot.respond /(?:rm|remove|del|delete) job (\d+)/i, (msg) ->
    id = msg.match[1]
    if JOBS[id]
      JOBS[id].stop()
      delete robot.brain.data.cronjob[id]
      msg.send "Job #{id} deleted"
    else
      msg.send "Job #{id} does not exist"

class Job
  constructor: (id, pattern, user, data, type) ->
    @id = id
    @pattern = pattern
    @user = user
    @data = data
    @type = type

  start: (robot) ->
    @cronjob = new cronJob(@pattern, =>
      if @type == "event"
        @sendEvent robot
      else
        @sendMessage robot
    )
    @cronjob.start()

  stop: ->
    @cronjob.stop()

  serialize: ->
    [@pattern, @user, @data, @type]

  sendMessage: (robot) ->
    robot.send @user, @data

  sendEvent: (robot) ->
    robot.emit @data.event, @data.payload

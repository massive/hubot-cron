# Description:
#   register cron jobs to schedule messages on the current channel
#
# Commands:
#   hubot new job "<crontab format>" <message> - Schedule a cron job to say something
#   hubot new event job "<crontab format>" <event> <params_as_json> - Schedule a cron job to emit an event
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

registerNewJob = (robot, id, pattern, user, payload, type) ->
  JOBS[id] = new Job(id, pattern, user, payload, type)
  JOBS[id].start(robot)
  JOBS[id]

module.exports = (robot) ->
  robot.brain.on 'loaded', =>
    robot.brain.data.cronjob or= {}
    for own id, job of robot.brain.data.cronjob
      registerNewJob robot, id, job[0], job[1], job[2]

  robot.respond /(?:new|add) (event\s)?job "(.*?)" (.+?)(\s(.*))?$/i, (msg) ->
    try
      type = "message"
      data = msg.match[3]

      if msg.match[1]?.trim() == "event"
        type = "event"
        data = event: msg.match[3].trim(), payload: msg.match[5]?.trim()

      id = createNewJob robot, msg.match[2], msg.message.user, data, type
      msg.send "Job #{type} #{id} created"
    catch error
      msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

  robot.respond /(?:list|ls) jobs?/i, (msg) ->
    for own id, job of robot.brain.data.cronjob
      msg.send "#{id}: #{job[0]} @#{job[1].room} \"#{JSON.stringify(job[2])}\""

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
      if @type == "message"
        @sendMessage robot
      else
        @sendEvent robot
    )
    @cronjob.start()

  stop: ->
    @cronjob.stop()

  serialize: ->
    [@pattern, @user, @data]

  sendMessage: (robot) ->
    robot.send @user, @data

  sendEvent: (robot) ->
    robot.emit @data.event, @data.payload


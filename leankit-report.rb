require 'date'
require 'leankitkanban'
require 'mail'
require 'nokogiri'
require 'spreadsheet'

require 'pry-debugger'

::PRIORITIES = {
  0 => 'Low',
  1 => 'Normal',
  2 => 'High',
  3 => 'Critical'
}

# SET UP CREDENTIALS
LeanKitKanban::Config.email = 'your.login@email.com'
LeanKitKanban::Config.password = 'your.password'
LeanKitKanban::Config.account = 'YOURCOMPANY.LEANKIT.COM'
LeanKitKanban::Config.debug = false

def get_tasks(board)
  board['Lanes'].map { |lane| lane['Cards'] }.flatten
end

def get_lanes(board)
  Hash[board['Lanes'].map { |l| [l['Id'], l] }]
end

def get_headers(lanes)
  lanes.select { |_id, l| l['ParentLaneId'] == 0 }
end

def get_header_id(lanes, task)
  header_ids = get_headers(lanes).keys
  lane_id = task['LaneId']
  parent_lane_id = lanes[lane_id]['ParentLaneId']
  while !parent_lane_id.to_s.empty? && parent_lane_id != 0 && !header_ids.include?(parent_lane_id) do
    lane_id = parent_lane_id
    parent_lane_id = lanes[lane_id]['ParentLaneId']
  end
  lane_id
end

def task_details(board_id, lanes, task)
  {
    external_id: task['ExternalCardID'],
    type: task['TypeName'],
    priority: PRIORITIES[task['Priority']],
    lane: lanes[get_header_id(lanes, task)]['Title'],
    title: Nokogiri::HTML(task['Title']).text,
    assigned: task['AssignedUserName'],
    blocked: task['IsBlocked'] ? 'blocked' : 'not blocked',
    url: "http://#{LeanKitKanban::Config.account.downcase}/Boards/View/#{board_id}/#{task['Id']}"
  }
end

def board_summary(board_id, card_types)
  puts "Retrieving board #{board_id}"
  board = LeanKitKanban::Board.find(board_id).flatten.first

  output = []
  lanes = get_lanes(board)
  tasks = get_tasks(board)

  tasks.each do |task|
    details = task_details(board_id, lanes, task)

    if card_types.include? task['TypeName']
      output << details
      # puts "  Output count is now #{output.count}"
    end

    totalcount = task['TaskBoardTotalSize']
    if !totalcount.nil? && totalcount > 1
      # puts "  Task #{task['Id']} has subtasks..."
      puts "  Retrieving task board for #{task['Id']}"
      taskboard = LeanKitKanban::TaskBoard.find(board_id, task['Id']).flatten.first
      boardlanes = get_lanes(taskboard)
      subtasks = get_tasks(taskboard)
      details = subtasks.select { |subtask| card_types.include? subtask['TypeName'] }.map { |subtask| task_details(board_id, boardlanes, subtask) }
      output = output.concat(details)
      # puts "  Output count is now #{output.count}"
    end
  end

  output
end

epics = board_summary(156_604_375, ['Epic'])
defects = board_summary(144_730_554, ['Defect'])
work = board_summary(144_730_554, ['Epic', 'Task', 'User Story'])

fname = "/tmp/leankit-report-#{DateTime.now.strftime('%Y%m%d')}.xls"
puts "Writing output to #{fname}"

# SET UP SPREADSHEET
book = Spreadsheet::Workbook.new
format = Spreadsheet::Format.new weight: :bold

sheet = book.create_worksheet name: 'Epic Status'
sheet.row(0).default_format = format
sheet.row(0).replace(%w(Title Blocked Lane))
epics.each_with_index do |row, n|
  sheet.row(n+1).replace([row[:title], row[:blocked], row[:lane]])
end

sheet = book.create_worksheet name: 'Defect Tracking'
sheet.row(0).default_format = format
sheet.row(0).replace(%w(ExternalID Type Priority Lane Assigned Blocked Title URL))
defects.each_with_index do |row, n|
  details = [row[:external_id], row[:type], row[:priority], row[:lane], row[:assigned], row[:blocked], row[:title], row[:url]]
  sheet.row(n+1).replace(details)
end
book.write fname

sheet = book.create_worksheet name: 'Work'
sheet.row(0).default_format = format
sheet.row(0).replace(%w(ExternalID Type Priority Lane Assigned Blocked Title URL))
work.each_with_index do |row, n|
  details = [row[:external_id], row[:type], row[:priority], row[:lane], row[:assigned], row[:blocked], row[:title], row[:url]]
  sheet.row(n+1).replace(details)
end
book.write fname

mail = Mail.new do
  from 'zahmad@teladoc.com'
  to 'zahmad@teladoc.com, sbhat@teladoc.com, suppuluri@teladoc.com, pmarkowitz@teladoc.com, jdittmar@teladoc.com, rkamat@teladoc.com'
  subject 'Behavioral Health Leankit Status'
  body 'See attached.'
  add_file fname
end
mail.delivery_method :sendmail
mail.deliver

puts "Done."

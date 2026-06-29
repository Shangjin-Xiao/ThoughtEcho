with open('lib/widgets/add_note_dialog.dart', 'r') as f:
    content = f.read()

content = content.replace(
    "'$_controller.originalWeather${_controller.originalTemperature != null ? \" $_controller.originalTemperature\" : \"\"}'",
    "'${_controller.originalWeather}${_controller.originalTemperature != null ? \" ${_controller.originalTemperature}\" : \"\"}'"
)

with open('lib/widgets/add_note_dialog.dart', 'w') as f:
    f.write(content)

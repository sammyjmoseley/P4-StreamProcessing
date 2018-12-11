class Query(object):
    def __init__(self, schema, commands):
        self._schema = schema
        self._commands = commands

    def install(self, p4info_helper, switch):
        for i in range(0, len(self._commands)):
            command = self._commands[i]
            command.install(p4info_helper, switch, self._schema, i)

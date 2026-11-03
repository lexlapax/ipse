ExUnit.start(autorun: false)
Code.require_file("native_notes_retained_probe.ex", __DIR__)
Ipse.Development.NativeNotesRetainedProbe.main(System.argv())

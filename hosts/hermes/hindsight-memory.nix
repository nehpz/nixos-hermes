# Host-local Hindsight memory substrate enablement. ONE-24 wires Hermes to
# consume this provider once the standalone API is validated.
{
  services.hindsightMemory = {
    enable = true;
    llama.enable = true;
  };
}

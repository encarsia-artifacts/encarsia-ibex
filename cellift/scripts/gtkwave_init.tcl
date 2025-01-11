set signals [list \
    "top.clk_i" \
    "top.rst_ni" \
]

gtkwave::addSignalsFromList $signals
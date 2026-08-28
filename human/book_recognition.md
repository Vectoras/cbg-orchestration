# Book recognition

This document is probably best described as a mixture or brainstorming and planning. I am throwing ideas here as I figure things out and make decisions. However, I will try to organise them as a plan / plans.

## The problem

A library of books that doesn't have an inventory system. Before I start working on that, the database, UI, etc. I am looking to find a solution that would help with identifying the books and find all the relevant details about them.

## The solution

From the bellow solutions I choose a combination of 3. and 2. The fastest and cheapest way is to scan the barcode on the back of the book and look up the so identified ISBN. Failing that I would use an AI to lookup multiple pictures of the book and try to identify it, first by trying to find the ISBN and failing that to look it up by title and author which I can assume will be easy to identify.

As quality control, a sample of successful ones should be veryfied by a human.

### 1. Whole shelf scanning (batch)

Take a photo of an entire shelf of books and let the automation identify it and look up all of them at once.

### 2. Single book scanning (individual)

Take a photo of a single book and let the automation identify it and look up the details. Even better, take the photo of the page that has the ISBN on it.

### 3. Barcode scanning on the back cover

Simple qr code scanning with the phone and thus extracting the ISBN straight away. Cheap, local, fast.

# TODO

* identify the models
* build a simple app that takes a photo and sends it to the model
